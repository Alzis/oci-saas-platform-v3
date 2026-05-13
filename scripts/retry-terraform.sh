#!/bin/bash

# ==============================================================================
# Script: retry-terraform.sh
# Description: Executa 'terraform apply' em um loop até que seja bem-sucedido.
#              Projetado para lidar com erros de capacidade intermitentes na OCI,
#              especialmente para instâncias Ampere A1 Free Tier.
# Author: Gemini Code Assist
# Version: 1.0
# ==============================================================================

# --- Configuração e Variáveis Globais ---
set -o pipefail # Garante que o código de saída de um pipeline seja o do comando que falhou

# Cores para o output
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_NC='\033[0m' # Sem Cor

# Arquivo de log
readonly LOG_FILE="terraform-retry.log"

# Diretório de lock para evitar execuções simultâneas (método portável)
readonly LOCK_DIR="/tmp/terraform_apply.lockdir"

# Variáveis para o resumo
START_TIME=$(date +%s)
ATTEMPTS=0
FINAL_STATUS="INTERROMPIDO"

# --- Funções ---

# Função para imprimir mensagens coloridas no console
print_color() {
  local color="$1"
  local message="$2"
  echo -e "${color}${message}${COLOR_NC}"
}

# Função de log que escreve no console (com cor) e em um arquivo (sem cor)
log() {
  local message="$1"
  local color="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local log_message="[$timestamp] $message"

  echo "$log_message" >> "$LOG_FILE"

  if [[ -n "$color" ]]; then
    print_color "$color" "$log_message"
  else
    echo "$log_message"
  fi
}

# Exibe o resumo final da execução
show_summary() {
    local end_time
    end_time=$(date +%s)
    local total_seconds=$((end_time - START_TIME))
    local total_time_human

    # Cálculo portável do tempo de execução (compatível com macOS e Linux)
    local hours=$((total_seconds / 3600))
    local minutes=$(( (total_seconds % 3600) / 60 ))
    local seconds=$((total_seconds % 60))
    total_time_human=$(printf "%02d horas, %02d minutos e %02d segundos" $hours $minutes $seconds)

    log "==================== Resumo da Execução ====================" "$COLOR_YELLOW"
    if [[ "$FINAL_STATUS" == "SUCESSO" ]]; then
        log "Status Final: $FINAL_STATUS" "$COLOR_GREEN"
    else
        log "Status Final: $FINAL_STATUS" "$COLOR_RED"
    fi
    log "Total de tentativas: ${ATTEMPTS}" "$COLOR_YELLOW"
    log "Tempo total de execução: ${total_time_human}" "$COLOR_YELLOW"
    log "============================================================" "$COLOR_YELLOW"
}

# Função de limpeza chamada ao interromper o script (CTRL+C) ou ao final
cleanup() {
  # O código de saída 130 corresponde a SIGINT (CTRL+C)
  if [[ $? -eq 130 && "$FINAL_STATUS" == "INTERROMPIDO" ]]; then
      log "Execução interrompida pelo usuário." "$COLOR_YELLOW"
  fi
  show_summary
  rmdir "$LOCK_DIR" 2>/dev/null # Remove o diretório de lock
}

# Valida se as dependências e condições para execução estão satisfeitas
validate_prerequisites() {
  log "Validando pré-requisitos..." "$COLOR_YELLOW"

  if ! command -v terraform &> /dev/null; then
    log "ERRO: O comando 'terraform' não foi encontrado. Por favor, instale o Terraform." "$COLOR_RED"
    exit 1
  fi

  if ! ls *.tf &> /dev/null; then
    log "ERRO: Nenhum arquivo .tf encontrado no diretório atual. Execute este script a partir do seu diretório de ambiente do Terraform (ex: terraform/environments/dev)." "$COLOR_RED"
    exit 1
  fi

  log "Pré-requisitos validados com sucesso." "$COLOR_GREEN"
}

# --- Ponto de Entrada do Script ---
main() {
  # Garante uma única instância usando um diretório como lock (método atômico e portável)
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    print_color "$COLOR_RED" "ERRO: Outra instância do script já está em execução. Lock: $LOCK_DIR"
    exit 1
  fi

  # Registra a função de limpeza para ser executada na saída (incluindo CTRL+C)
  trap cleanup EXIT

  > "$LOG_FILE" # Limpa o arquivo de log para a nova execução

  log "Iniciando o script de retry do Terraform..." "$COLOR_YELLOW"
  log "Os logs serão salvos em: ${LOG_FILE}" "$COLOR_YELLOW"
  log "Pressione CTRL+C a qualquer momento para interromper." "$COLOR_YELLOW"

  validate_prerequisites

  # --- Configurações do Ciclo de Tentativas ---
  # Array de configurações de VM a tentar, em ordem. Formato: "OCPUs:MemoriaEmGB:Shape"
  local -a configurations
  configurations=( # Apenas a configuração Always Free para máxima compatibilidade
    "1:1:VM.Standard.E2.1.Micro"
  )
  # Array de Availability Domains (índices) a tentar.
  local -a availability_domains
  availability_domains=(0 1 2)

  local readonly short_wait_seconds=2
  local readonly long_wait_seconds=10

  log "Iniciando ciclo de tentativas com as seguintes configurações (de maior para menor):" "$COLOR_YELLOW"
  for config in "${configurations[@]}"; do
    log " - VM: ${config}" "$COLOR_YELLOW"
  done
  log "Availability Domains (Índices): 0, 1, 2" "$COLOR_YELLOW"

  # Loop do ciclo completo
  while true; do
    # Loop pelos Availability Domains
    for ad_index in "${availability_domains[@]}"; do
      # Loop pelas configurações de VM
      for config in "${configurations[@]}"; do
        ((ATTEMPTS++))
        
        local ocpus memory shape
        IFS=':' read -r ocpus memory shape <<< "$config"

        log "--- Tentativa #${ATTEMPTS} (AD: ${ad_index}, Config: ${ocpus} OCPU, ${memory}GB RAM, Shape: ${shape}) ---" "$COLOR_YELLOW"

        # Executa o terraform apply com as variáveis da configuração atual
        # Para formas não-Flex (ex: Micro), OCPUs e memória não são configuráveis e os parâmetros são ignorados pelo Terraform.
        { terraform apply -auto-approve -no-color \
            -var="availability_domain_index=${ad_index}" \
            -var="instance_shape=${shape}" \
            -var="instance_ocpus=${ocpus}" \
            -var="instance_memory_in_gbs=${memory}"; } 2>&1 | tee -a "$LOG_FILE"
        local tf_exit_code=${PIPESTATUS[0]}

        if [ $tf_exit_code -eq 0 ]; then
          log "SUCESSO: Terraform apply executado com sucesso na tentativa #${ATTEMPTS} em AD-${ad_index} com ${ocpus} OCPUs, ${memory}GB RAM e shape ${shape}." "$COLOR_GREEN"
          FINAL_STATUS="SUCESSO"
          exit 0 # Sucesso, a função cleanup será chamada pelo trap
        else
          log "FALHA: Tentativa #${ATTEMPTS} falhou com código de saída ${tf_exit_code}." "$COLOR_RED"
          log "Aguardando ${short_wait_seconds} segundos antes da próxima tentativa..." "$COLOR_YELLOW"
          sleep "$short_wait_seconds"
        fi
      done # Fim do loop de configurações de VM
    done # Fim do loop de ADs

    log "Todas as combinações falharam neste ciclo. Aguardando ${long_wait_seconds} segundos para reiniciar." "$COLOR_YELLOW"
    sleep "$long_wait_seconds"
  done # Fim do loop de ciclo
}

main "$@"
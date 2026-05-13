
# OCI SaaS Platform Demo

Arquitetura:

Bucket (Front-end SPA)
        ↓
CloudFront/CDN opcional
        ↓
API Node.js (VM OCI)
        ↓
Redis + MySQL

## Stack

- Oracle OCI Free Tier
- Terraform
- Docker
- Node.js API
- React Frontend
- Redis
- MySQL
- Portainer
- Semaphore UI
- PMM
- XtraBackup

## Fluxo

Frontend hospedado em bucket.
Frontend consome API pública da VM OCI.

# oci-saas-platform
# oci-saas-platform-v2


terraform apply -auto-approve \
        -var="availability_domain_index=1" \
        -var="instance_shape=VM.Standard.E2.1.Micro" \
        -var="instance_ocpus=1" \
        -var="instance_memory_in_gbs=1";
# oci-saas-platform-v3

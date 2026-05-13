
### STAGE 1: Dependencies ###
# This stage installs dependencies and is cached separately.
FROM node:20-slim AS dependencies

WORKDIR /app

# Copy package.json and package-lock.json. Using a lock file is crucial for reproducible builds.
COPY package.json package-lock.json* ./

# Install production dependencies using `npm ci`, which is faster and more secure than `npm install`.
RUN npm install --omit=production


### STAGE 2: Production ###
# This stage builds the final, lean production image.
FROM node:20-slim

WORKDIR /app

# Create a non-root user and group for security.
RUN addgroup --system --gid 1001 appgroup && \
    adduser --system --uid 1001 --ingroup appgroup appuser
USER appuser

# Copy pre-installed node_modules from the 'dependencies' stage with correct ownership.
COPY --from=dependencies --chown=appuser:appgroup /app/node_modules ./node_modules

# Copy the rest of the application code, also with correct ownership.
COPY --chown=appuser:appgroup . .

EXPOSE 3003

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3003/health || exit 1

CMD ["node", "server.js"]

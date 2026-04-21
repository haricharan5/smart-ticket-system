FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
ARG VITE_API_URL
ARG VITE_POWERBI_URL
ENV VITE_API_URL=$VITE_API_URL
ENV VITE_POWERBI_URL=$VITE_POWERBI_URL
RUN npm run build

FROM nginx:alpine

# Copy built React app
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx config (HTTPS-enabled)
COPY nginx.conf /etc/nginx/conf.d/default.conf

# SSL cert directory — certs are mounted at runtime via volume or copied below
ARG SSL_CERT_PATH=/certs
COPY ${SSL_CERT_PATH}/smartticket.crt /etc/ssl/smartticket/smartticket.crt 2>/dev/null || true
COPY ${SSL_CERT_PATH}/smartticket.key /etc/ssl/smartticket/smartticket.key 2>/dev/null || true

EXPOSE 80 443
CMD ["nginx", "-g", "daemon off;"]

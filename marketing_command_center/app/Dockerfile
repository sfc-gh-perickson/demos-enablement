1... FROM node:20-alpine AS builder
2... WORKDIR /app
3... COPY package.json package-lock.json* ./
4... RUN npm ci
5... COPY . .
6... RUN npm run build
7... 
8... FROM node:20-alpine
9... RUN apk add --no-cache nginx
10... COPY --from=builder /app/dist /usr/share/nginx/html
11... COPY nginx.conf /etc/nginx/http.d/default.conf
12... COPY api-proxy.js /app/api-proxy.js
13... COPY entrypoint.sh /entrypoint.sh
14... RUN chmod +x /entrypoint.sh
15... EXPOSE 80
16... ENTRYPOINT ["/entrypoint.sh"]
17... 
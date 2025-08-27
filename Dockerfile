# Use an official Node.js image as the base
FROM node:18-alpine

# Set working directory
WORKDIR /usr/src/app

# Copy static files
COPY mario-clone/ ./

# Install a simple static server
RUN npm install -g serve

# Expose port 8080
EXPOSE 8080

# Start the static server
CMD ["serve", "-s", ".", "-l", "8080"]

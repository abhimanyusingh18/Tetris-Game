# Stage 1: Build the React application
FROM node:20-alpine AS build
WORKDIR /app

# Copy package.json and yarn.lock
COPY package.json yarn.lock ./

# Install dependencies
RUN yarn install

# Copy the rest of the application code
COPY . .

# Build the application
RUN yarn build

# Stage 2: Serve the application with Node.js
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Install the serve package
RUN yarn global add serve

# Copy the compiled build artifacts from Stage 1
COPY --from=build /app/build ./build

# Expose port 80
EXPOSE 80

# Start serve
CMD ["serve", "-s", "build", "-l", "80"]

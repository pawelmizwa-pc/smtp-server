#!/bin/bash

# Quick deployment script for Alpine Linux Dartnode server
# Run this after SSH'ing into your server

set -e

echo "🚀 Starting SMTP Server deployment on Alpine Linux..."

# Update system
echo "📦 Updating Alpine packages..."
apk update && apk upgrade

# Install Node.js and npm
echo "📦 Installing Node.js and npm..."
apk add nodejs npm

# Install git for code deployment
echo "📦 Installing git..."
apk add git

# Install PM2
echo "📦 Installing PM2..."
npm install -g pm2

# Create app directory
echo "📁 Creating application directory..."
mkdir -p /var/www/smtp-server
cd /var/www/smtp-server

echo "✅ Alpine Linux server setup complete!"
echo ""
echo "Next steps:"
echo "1. Upload your code to /var/www/smtp-server/"
echo "2. Create .env file with your Gmail credentials"
echo "3. Run: npm install"
echo "4. Run: pm2 start server.js --name smtp-server"
echo "5. Run: pm2 save && pm2 startup"
echo ""
echo "Your server will be available at: http://38.45.89.8:3000"
echo ""
echo "Alpine-specific notes:"
echo "- Use 'apk' instead of 'apt' for package management"
echo "- Use 'rc-service' and 'rc-update' for service management"
echo "- Use 'vi' editor (or install nano with: apk add nano)"
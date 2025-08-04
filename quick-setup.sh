#!/bin/bash

# 🚀 Quick SMTP Server Setup Script
# Automated installation of self-hosted SMTP server with unlimited email sending
# Compatible with Ubuntu 22.04

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${PURPLE}===================================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}===================================================${NC}"
}

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root!"
        print_error "Please run: sudo ./quick-setup.sh"
        exit 1
    fi
}

# Check Ubuntu version
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine OS version"
        exit 1
    fi
    
    . /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]]; then
        print_error "This script is designed for Ubuntu only"
        print_error "Detected OS: $ID"
        exit 1
    fi
    
    if [[ "$VERSION_ID" < "22.04" ]]; then
        print_warning "This script is tested on Ubuntu 22.04+"
        print_warning "Your version: $VERSION_ID"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    print_status "OS Check: Ubuntu $VERSION_ID ✅"
}

# Get user input
get_user_input() {
    print_header "📝 Configuration Setup"
    
    # Domain name
    while [[ -z "$DOMAIN" ]]; do
        read -p "🌐 Enter your domain name (e.g., example.com): " DOMAIN
        if [[ -z "$DOMAIN" ]]; then
            print_error "Domain name is required!"
        fi
    done
    
    # Server IP
    SERVER_IP=$(curl -s https://ipv4.icanhazip.com)
    print_status "🔍 Auto-detected server IP: $SERVER_IP"
    read -p "📡 Confirm server IP or enter manually [$SERVER_IP]: " USER_IP
    if [[ -n "$USER_IP" ]]; then
        SERVER_IP="$USER_IP"
    fi
    
    # Client IP for whitelist
    CLIENT_IP=$(curl -s https://ipv4.icanhazip.com)
    print_status "🔍 Auto-detected your current IP: $CLIENT_IP"
    read -p "🔒 Confirm your IP for whitelist or enter manually [$CLIENT_IP]: " USER_CLIENT_IP
    if [[ -n "$USER_CLIENT_IP" ]]; then
        CLIENT_IP="$USER_CLIENT_IP"
    fi
    
    # Email settings
    read -p "📧 Enter 'from' email address [noreply@$DOMAIN]: " SMTP_FROM
    if [[ -z "$SMTP_FROM" ]]; then
        SMTP_FROM="noreply@$DOMAIN"
    fi
    
    # Rate limiting
    read -p "⚡ Email rate limit per minute [100]: " RATE_LIMIT
    if [[ -z "$RATE_LIMIT" ]]; then
        RATE_LIMIT="100"
    fi
    
    print_header "📋 Configuration Summary"
    echo -e "${BLUE}Domain:${NC} $DOMAIN"
    echo -e "${BLUE}Server IP:${NC} $SERVER_IP"
    echo -e "${BLUE}Client IP:${NC} $CLIENT_IP"
    echo -e "${BLUE}Mail hostname:${NC} mail.$DOMAIN"
    echo -e "${BLUE}From email:${NC} $SMTP_FROM"
    echo -e "${BLUE}Rate limit:${NC} $RATE_LIMIT emails/minute"
    echo
    
    read -p "🤔 Continue with this configuration? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_error "Setup cancelled by user"
        exit 1
    fi
}

# Update system
update_system() {
    print_step "🔄 Updating system packages..."
    apt update -qq
    apt upgrade -y -qq
    print_status "System updated successfully"
}

# Set hostname
setup_hostname() {
    print_step "🏷️ Setting up hostname..."
    
    hostnamectl set-hostname "mail.$DOMAIN"
    echo "127.0.0.1 mail.$DOMAIN" >> /etc/hosts
    
    # Verify
    CURRENT_HOSTNAME=$(hostname -f)
    if [[ "$CURRENT_HOSTNAME" == "mail.$DOMAIN" ]]; then
        print_status "Hostname set to: $CURRENT_HOSTNAME ✅"
    else
        print_warning "Hostname verification failed: $CURRENT_HOSTNAME"
    fi
}

# Install essential packages
install_packages() {
    print_step "📦 Installing essential packages..."
    
    # Install basic tools
    apt install -y curl wget git nano ufw bind9-utils
    
    # Install Node.js 18 LTS
    print_status "Installing Node.js 18 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - > /dev/null 2>&1
    apt install -y nodejs
    
    # Install Postfix (non-interactive)
    print_status "Installing Postfix..."
    debconf-set-selections <<< "postfix postfix/mailname string $DOMAIN"
    debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
    apt install -y postfix postfix-policyd-spf-python mailutils
    
    # Install OpenDKIM
    print_status "Installing OpenDKIM..."
    apt install -y opendkim opendkim-tools
    
    # Verify installations
    node_version=$(node --version)
    npm_version=$(npm --version)
    print_status "Node.js: $node_version, npm: $npm_version ✅"
}

# Configure Postfix
configure_postfix() {
    print_step "📮 Configuring Postfix..."
    
    # Backup original
    cp /etc/postfix/main.cf /etc/postfix/main.cf.backup
    
    # Create new configuration
    cat > /etc/postfix/main.cf << EOF
# Basic Postfix configuration for $DOMAIN
myhostname = mail.$DOMAIN
mydomain = $DOMAIN
myorigin = \$mydomain
inet_interfaces = localhost
inet_protocols = all
mydestination = \$myhostname, localhost

# Network and message settings
message_size_limit = 10485760
mailbox_size_limit = 1073741824

# SMTP settings
smtp_tls_security_level = may
smtp_tls_note_starttls_offer = yes

# SMTPD settings
smtpd_tls_security_level = may
smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination

# OpenDKIM integration
milter_protocol = 2
milter_default_action = accept
smtpd_milters = unix:/var/run/opendkim/opendkim.sock
non_smtpd_milters = unix:/var/run/opendkim/opendkim.sock
EOF

    # Enable submission port (587)
    print_status "Enabling SMTP submission port 587..."
    
    # Backup master.cf
    cp /etc/postfix/master.cf /etc/postfix/master.cf.backup
    
    # Enable submission service
    sed -i 's/#submission inet n       -       y       -       -       smtpd/submission inet n       -       y       -       -       smtpd/' /etc/postfix/master.cf
    sed -i '/^submission inet/,/^[[:space:]]*$/ {
        s/#  -o syslog_name=postfix\/submission/  -o syslog_name=postfix\/submission/
        s/#  -o smtpd_tls_security_level=encrypt/  -o smtpd_tls_security_level=may/
        s/#  -o smtpd_sasl_auth_enable=yes/  -o smtpd_sasl_auth_enable=no/
        s/#  -o smtpd_reject_unlisted_recipient=no/  -o smtpd_reject_unlisted_recipient=no/
    }' /etc/postfix/master.cf
    
    print_status "Postfix configured successfully ✅"
}

# Configure OpenDKIM
configure_opendkim() {
    print_step "🔐 Configuring OpenDKIM..."
    
    # Create directories
    mkdir -p /etc/opendkim/keys
    chown -R opendkim:opendkim /etc/opendkim
    
    # Generate DKIM key
    print_status "Generating DKIM key for $DOMAIN..."
    sudo -u opendkim opendkim-genkey -s default -d "$DOMAIN" -D /etc/opendkim/keys/
    
    # Create OpenDKIM configuration
    cat > /etc/opendkim.conf << EOF
AutoRestart             Yes
AutoRestartRate         10/1h
LogWhy                  Yes
Syslog                  Yes
SyslogSuccess           Yes
Mode                    sv
Canonicalization        relaxed/simple
ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
SignatureAlgorithm      rsa-sha256
Socket                  local:/var/run/opendkim/opendkim.sock
PidFile                 /var/run/opendkim/opendkim.pid
UserID                  opendkim:opendkim
TemporaryDirectory      /var/tmp
EOF

    # Create trusted hosts
    cat > /etc/opendkim/TrustedHosts << EOF
127.0.0.1
localhost
192.168.0.1/24
10.0.0.1/8
172.16.0.1/12
*.$DOMAIN
EOF

    # Create key table
    echo "default._domainkey.$DOMAIN $DOMAIN:default:/etc/opendkim/keys/default.private" > /etc/opendkim/KeyTable
    
    # Create signing table
    echo "*@$DOMAIN default._domainkey.$DOMAIN" > /etc/opendkim/SigningTable
    
    # Set permissions
    chown -R opendkim:opendkim /etc/opendkim
    chmod 600 /etc/opendkim/keys/default.private
    
    print_status "OpenDKIM configured successfully ✅"
}

# Start mail services
start_mail_services() {
    print_step "🚀 Starting mail services..."
    
    systemctl enable postfix opendkim
    systemctl restart opendkim
    sleep 2
    systemctl restart postfix
    
    # Check if services are running
    if systemctl is-active --quiet postfix; then
        print_status "Postfix is running ✅"
    else
        print_error "Postfix failed to start!"
        exit 1
    fi
    
    if systemctl is-active --quiet opendkim; then
        print_status "OpenDKIM is running ✅"
    else
        print_error "OpenDKIM failed to start!"
        exit 1
    fi
    
    # Check if port 587 is listening
    if ss -tlnp | grep -q ":587"; then
        print_status "SMTP submission port 587 is active ✅"
    else
        print_error "Port 587 is not listening!"
        exit 1
    fi
}

# Setup Node.js API
setup_nodejs_api() {
    print_step "⚙️ Setting up Node.js SMTP API..."
    
    # Create project directory
    mkdir -p /var/www/smtp-server
    cd /var/www/smtp-server
    
    # Initialize package.json
    cat > package.json << EOF
{
  "name": "smtp-server",
  "version": "1.0.0",
  "description": "Self-hosted SMTP server for unlimited email sending",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "keywords": ["smtp", "email", "postfix", "unlimited"],
  "author": "SMTP Server Setup",
  "license": "MIT"
}
EOF

    # Install dependencies
    print_status "Installing Node.js dependencies..."
    npm install nodemailer fastify @fastify/cors dotenv --silent
    
    # Create server.js
    cat > server.js << 'EOF'
require("dotenv").config();
const fastify = require("fastify")({ logger: true });
const nodemailer = require("nodemailer");

// Enable CORS
fastify.register(require("@fastify/cors"), {
  origin: true,
});

// IP Whitelist configuration
const allowedIPs = [
  '127.0.0.1',           // localhost
  '::1',                 // localhost IPv6
  'SERVER_IP_PLACEHOLDER',      // your server IP
  'CLIENT_IP_PLACEHOLDER',      // your current IP
  // Add more IPs as needed
];

function isIPAllowed(ip) {
  if (!ip) return false;
  
  const cleanIP = ip.replace(/^::ffff:/, '');
  console.log(`🔍 Checking IP: ${cleanIP}`);
  
  const allowed = allowedIPs.includes(cleanIP);
  
  if (allowed) {
    console.log(`✅ Access granted for IP: ${cleanIP}`);
  } else {
    console.log(`❌ Access denied for IP: ${cleanIP}`);
    console.log(`📋 Allowed IPs: ${allowedIPs.join(', ')}`);
  }
  
  return allowed;
}

// IP whitelist middleware - protect ALL endpoints
fastify.addHook('preHandler', async (request, reply) => {
  const clientIP = request.ip || 
                   request.headers['x-forwarded-for']?.split(',')[0] || 
                   request.headers['x-real-ip'] || 
                   request.socket.remoteAddress;
  
  if (!isIPAllowed(clientIP)) {
    reply.status(403).send({
      error: 'Access Denied',
      message: 'Your IP is not authorized to use this service',
      ip: clientIP ? clientIP.replace(/^::ffff:/, '') : 'unknown',
      timestamp: new Date().toISOString()
    });
    return;
  }
});

// Configure SMTP transporter
const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || "localhost",
  port: process.env.SMTP_PORT || 587,
  secure: false,
  requireTLS: false,
  ignoreTLS: true,
  auth: false, // No auth for local server
});

// Verify SMTP connection on startup
transporter.verify((error, success) => {
  if (error) {
    console.log("SMTP connection error:", error);
  } else {
    console.log("SMTP server is ready to send emails");
  }
});

// Email queue and rate limiting
const emailQueue = [];
let isProcessing = false;
let lastEmailTime = 0;
const RATE_LIMIT = parseInt(process.env.SMTP_RATE_LIMIT) || 100;
const RETRY_DELAY = parseInt(process.env.RETRY_DELAY) || 1000;

// Process email queue
async function processEmailQueue() {
  if (isProcessing || emailQueue.length === 0) return;
  
  isProcessing = true;
  console.log(`Processing email queue. ${emailQueue.length} emails pending.`);
  
  while (emailQueue.length > 0) {
    const emailData = emailQueue.shift();
    
    try {
      const now = Date.now();
      const timeSinceLastEmail = now - lastEmailTime;
      const minInterval = 60000 / RATE_LIMIT;
      
      if (timeSinceLastEmail < minInterval) {
        await new Promise(resolve => setTimeout(resolve, minInterval - timeSinceLastEmail));
      }
      
      console.log(`Sending email ${emailData.id} to ${emailData.to}`);
      
      const info = await transporter.sendMail({
        from: emailData.from || process.env.SMTP_FROM || 'noreply@localhost',
        to: emailData.to,
        subject: emailData.subject,
        text: emailData.text,
        html: emailData.html,
        messageId: emailData.messageId,
      });
      
      lastEmailTime = Date.now();
      console.log(`Email sent successfully: ${info.messageId}`);
      
    } catch (error) {
      console.error(`Failed to send email ${emailData.id}:`, error);
      
      if (emailData.retries < 3) {
        emailData.retries++;
        emailQueue.push(emailData);
        console.log(`Retrying email ${emailData.id} (attempt ${emailData.retries})`);
      }
    }
    
    await new Promise(resolve => setTimeout(resolve, RETRY_DELAY));
  }
  
  isProcessing = false;
  console.log("Email queue processing completed.");
}

// Health check endpoint
fastify.get("/health", async (request, reply) => {
  return { 
    status: "OK", 
    message: "SMTP server is running",
    timestamp: new Date().toISOString(),
    version: "1.0.0"
  };
});

// Send email endpoint
fastify.post("/send-email", async (request, reply) => {
  try {
    const { to, subject, text, html, from } = request.body;
    
    if (!to || !subject || (!text && !html)) {
      return reply.status(400).send({
        success: false,
        message: "Missing required fields: to, subject, and (text or html)"
      });
    }
    
    const messageId = `<${Date.now()}.${Math.random().toString(36).substr(2, 9)}@DOMAIN_PLACEHOLDER>`;
    
    const emailData = {
      id: `${Date.now()}.${Math.random().toString(36).substr(2, 4)}`,
      to,
      subject,
      text,
      html,
      from,
      messageId,
      retries: 0,
      timestamp: Date.now()
    };
    
    emailQueue.push(emailData);
    console.log(`✅ Email queued. Queue length: ${emailQueue.length}`);
    
    processEmailQueue();
    
    return {
      success: true,
      messageId: messageId,
      message: "Email sent successfully"
    };
    
  } catch (error) {
    console.error("Error sending email:", error);
    return reply.status(500).send({
      success: false,
      message: "Internal server error"
    });
  }
});

// Queue status endpoint
fastify.get("/queue-status", async (request, reply) => {
  return {
    queueLength: emailQueue.length,
    isProcessing: isProcessing,
    lastEmailTime: lastEmailTime,
    rateLimitMs: RATE_LIMIT,
    timestamp: new Date().toISOString()
  };
});

// Start server
const start = async () => {
  try {
    const port = process.env.PORT || 3000;
    const host = process.env.HOST || "0.0.0.0";
    
    await fastify.listen({ port: port, host: host });
    console.log(`🚀 Server running on http://${host}:${port}`);
    console.log(`🔒 IP whitelist protection enabled`);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
};

start();
EOF

    # Replace placeholders in server.js
    sed -i "s/SERVER_IP_PLACEHOLDER/$SERVER_IP/g" server.js
    sed -i "s/CLIENT_IP_PLACEHOLDER/$CLIENT_IP/g" server.js
    sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" server.js
    
    # Create .env file
    cat > .env << EOF
# SMTP Configuration
SMTP_HOST=localhost
SMTP_PORT=587
SMTP_SECURE=false
SMTP_FROM=$SMTP_FROM

# Performance settings
SMTP_RATE_LIMIT=$RATE_LIMIT
RETRY_DELAY=1000

# API Server
PORT=3000
HOST=0.0.0.0
EOF

    print_status "Node.js API created successfully ✅"
}

# Setup PM2
setup_pm2() {
    print_step "🔄 Setting up PM2 process manager..."
    
    # Install PM2 globally
    npm install -g pm2 --silent
    
    # Create ecosystem configuration
    cat > /var/www/smtp-server/ecosystem.config.js << EOF
module.exports = {
  apps: [
    {
      name: 'smtp-server',
      script: 'server.js',
      cwd: '/var/www/smtp-server',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      env: {
        NODE_ENV: 'production',
        PORT: 3000,
        HOST: '0.0.0.0'
      }
    }
  ]
};
EOF

    # Start with PM2
    cd /var/www/smtp-server
    pm2 start ecosystem.config.js
    pm2 save
    
    # Set up PM2 to start on boot
    env PATH=$PATH:/usr/bin pm2 startup systemd -u root --hp /root
    
    print_status "PM2 configured and running ✅"
}

# Configure firewall
configure_firewall() {
    print_step "🔒 Configuring security firewall..."
    
    # Reset UFW to defaults
    ufw --force reset > /dev/null 2>&1
    
    # Block external SMTP access (force API-only)
    ufw deny from any to any port 25
    ufw deny from any to any port 587
    ufw deny from any to any port 465
    
    # Allow only localhost SMTP
    ufw allow from 127.0.0.1 to any port 587
    
    # Allow SSH and HTTPS
    ufw allow 22
    ufw allow 443
    ufw allow 80
    
    # Enable firewall
    ufw --force enable > /dev/null 2>&1
    
    print_status "Firewall configured - SMTP ports blocked externally ✅"
}

# Test installation
test_installation() {
    print_step "🧪 Testing installation..."
    
    # Wait for services to stabilize
    sleep 5
    
    # Test health endpoint
    if curl -s http://localhost:3000/health > /dev/null; then
        print_status "✅ API health check passed"
    else
        print_error "❌ API health check failed"
        return 1
    fi
    
    # Test queue status
    if curl -s http://localhost:3000/queue-status > /dev/null; then
        print_status "✅ Queue status endpoint working"
    else
        print_error "❌ Queue status endpoint failed"
        return 1
    fi
    
    print_status "🎉 All tests passed!"
}

# Display DKIM key
show_dkim_key() {
    print_header "🔑 DKIM Public Key"
    echo -e "${YELLOW}Add this TXT record to your DNS:${NC}"
    echo -e "${BLUE}Name:${NC} default._domainkey"
    echo -e "${BLUE}Content:${NC}"
    cat /etc/opendkim/keys/default.txt
    echo
}

# Display DNS requirements
show_dns_requirements() {
    print_header "🌐 Required DNS Records"
    echo -e "${YELLOW}Add these records to your DNS (Cloudflare):${NC}"
    echo
    echo -e "${CYAN}1. A Record:${NC}"
    echo -e "   Name: mail"
    echo -e "   Content: $SERVER_IP"
    echo -e "   Proxy: ❌ DNS only"
    echo
    echo -e "${CYAN}2. MX Record:${NC}"
    echo -e "   Name: @"
    echo -e "   Content: 10 mail.$DOMAIN"
    echo -e "   Proxy: ❌ DNS only"
    echo
    echo -e "${CYAN}3. SPF Record (TXT):${NC}"
    echo -e "   Name: @"
    echo -e "   Content: v=spf1 ip4:$SERVER_IP ~all"
    echo -e "   Proxy: ❌ DNS only"
    echo
    echo -e "${CYAN}4. DKIM Record (TXT):${NC}"
    echo -e "   Name: default._domainkey"
    echo -e "   Content: [See DKIM key above]"
    echo -e "   Proxy: ❌ DNS only"
    echo
    echo -e "${CYAN}5. DMARC Record (TXT):${NC}"
    echo -e "   Name: _dmarc"
    echo -e "   Content: v=DMARC1; p=quarantine; rua=mailto:admin@$DOMAIN"
    echo -e "   Proxy: ❌ DNS only"
    echo
}

# Display final instructions
show_final_instructions() {
    print_header "🎉 Installation Complete!"
    
    echo -e "${GREEN}✅ Your SMTP server is now running!${NC}"
    echo
    echo -e "${CYAN}🔧 Services Status:${NC}"
    echo -e "   • Postfix: $(systemctl is-active postfix)"
    echo -e "   • OpenDKIM: $(systemctl is-active opendkim)"
    echo -e "   • Node.js API: $(pm2 info smtp-server | grep -q "online" && echo "online" || echo "offline")"
    echo
    echo -e "${CYAN}📡 API Endpoints:${NC}"
    echo -e "   • Health: http://localhost:3000/health"
    echo -e "   • Send Email: http://localhost:3000/send-email"
    echo -e "   • Queue Status: http://localhost:3000/queue-status"
    echo
    echo -e "${CYAN}🔒 Security:${NC}"
    echo -e "   • IP Whitelist: Enabled (Server: $SERVER_IP, Client: $CLIENT_IP)"
    echo -e "   • Firewall: SMTP ports blocked externally"
    echo -e "   • API-only: Direct SMTP access disabled"
    echo
    echo -e "${CYAN}📝 Next Steps:${NC}"
    echo -e "   1. Add the DNS records shown above"
    echo -e "   2. Set up Cloudflare Tunnel for HTTPS access"
    echo -e "   3. Test email sending with the API"
    echo
    echo -e "${CYAN}🧪 Test Email Sending:${NC}"
    echo -e "   curl -X POST http://localhost:3000/send-email \\"
    echo -e "     -H \"Content-Type: application/json\" \\"
    echo -e "     -d '{"
    echo -e "       \"to\": \"test@gmail.com\","
    echo -e "       \"subject\": \"🚀 SMTP Test\","
    echo -e "       \"text\": \"Your unlimited SMTP server is working!\""
    echo -e "     }'"
    echo
    echo -e "${CYAN}📚 Useful Commands:${NC}"
    echo -e "   • Check status: pm2 status"
    echo -e "   • View logs: pm2 logs smtp-server"
    echo -e "   • Check queue: postqueue -p"
    echo -e "   • Restart API: pm2 restart smtp-server"
    echo
    echo -e "${YELLOW}⚠️  Important:${NC}"
    echo -e "   • DNS changes may take up to 24 hours to propagate"
    echo -e "   • Set up PTR records with your hosting provider"
    echo -e "   • Consider setting up Cloudflare Tunnel for public HTTPS access"
    echo
    print_status "🚀 Enjoy unlimited email sending!"
}

# Main execution
main() {
    clear
    print_header "🚀 SMTP Server Quick Setup"
    echo -e "${CYAN}Self-hosted SMTP server with unlimited email sending${NC}"
    echo -e "${CYAN}Compatible with Ubuntu 22.04+${NC}"
    echo
    
    # Pre-flight checks
    check_root
    check_os
    
    # Get configuration
    get_user_input
    
    # Installation steps
    update_system
    setup_hostname
    install_packages
    configure_postfix
    configure_opendkim
    start_mail_services
    setup_nodejs_api
    setup_pm2
    configure_firewall
    
    # Testing
    if test_installation; then
        # Display results
        show_dkim_key
        show_dns_requirements
        show_final_instructions
    else
        print_error "Installation test failed. Please check the logs."
        exit 1
    fi
}

# Run main function
main "$@"
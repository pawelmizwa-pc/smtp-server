# 🚀 Self-Hosted SMTP Server with Unlimited Email Sending

**Complete setup guide for bypassing Gmail's 2000 email daily limit with your own SMTP server**

## 📋 **Overview**

This guide shows how to build a production-ready, self-hosted SMTP server that:

- ✅ **Sends unlimited emails** (no Gmail restrictions)
- ✅ **Uses your own domain** (professional email addresses)
- ✅ **Has public HTTPS API** (secure Cloudflare tunnel)
- ✅ **Runs in background** (PM2 process management)
- ✅ **IP whitelisted** (security protection)
- ✅ **Proper authentication** (DKIM, SPF, DMARC)

## 🏗️ **Architecture**

```
Internet → Cloudflare Tunnel → Node.js API → Postfix → Email Recipients
          (HTTPS Security)    (Rate Limiting) (SMTP+DKIM)
```

**Components:**

- **Ubuntu 22.04** - Server OS (better than Alpine for DNS)
- **Postfix** - Mail Transfer Agent (SMTP server)
- **OpenDKIM** - Email authentication (prevents spam)
- **Node.js + Fastify** - Email API with queue management
- **PM2** - Process manager (auto-restart, background)
- **Cloudflare Tunnel** - Secure HTTPS public access
- **UFW Firewall** - Security (block direct SMTP access)

---

## 🛠️ **Prerequisites**

### **Required:**

- **Ubuntu 22.04 Server** (dedicated/VPS)
- **Domain name** (e.g., `pragmaticmeet.com`)
- **Cloudflare account** (free tier works)
- **Root/sudo access** to server

### **DNS Requirements:**

- Domain nameservers pointed to Cloudflare
- Ability to add DNS records

---

## 📖 **Step-by-Step Setup**

### **Step 1: Server Preparation**

```bash
# Connect to your Ubuntu server
ssh root@YOUR_SERVER_IP

# Update system
apt update && apt upgrade -y

# Set hostname for mail server
hostnamectl set-hostname mail.YOUR_DOMAIN.com
echo "127.0.0.1 mail.YOUR_DOMAIN.com" >> /etc/hosts

# Verify hostname
hostname -f
```

### **Step 2: Install Required Packages**

```bash
# Install essential packages
apt install -y curl wget git nano ufw

# Install Node.js 18 LTS
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# Verify installation
node --version
npm --version
```

### **Step 3: Install and Configure Postfix + OpenDKIM**

```bash
# Install Postfix and related packages
apt install -y postfix postfix-policyd-spf-python mailutils

# Install OpenDKIM for email authentication
apt install -y opendkim opendkim-tools

# During Postfix installation, choose:
# 1. "Internet Site"
# 2. Mail name: "YOUR_DOMAIN.com"
```

### **Step 4: Configure Postfix**

```bash
# Backup original configuration
cp /etc/postfix/main.cf /etc/postfix/main.cf.backup

# Create Postfix configuration
cat > /etc/postfix/main.cf << 'EOF'
# Basic Postfix configuration
myhostname = mail.YOUR_DOMAIN.com
mydomain = YOUR_DOMAIN.com
myorigin = $mydomain
inet_interfaces = all
inet_protocols = all
mydestination = $myhostname, localhost

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
```

### **Step 5: Configure OpenDKIM**

```bash
# Create OpenDKIM directories
mkdir -p /etc/opendkim/keys
chown -R opendkim:opendkim /etc/opendkim

# Generate DKIM key for your domain
sudo -u opendkim opendkim-genkey -s default -d YOUR_DOMAIN.com -D /etc/opendkim/keys/

# Create OpenDKIM configuration
cat > /etc/opendkim.conf << 'EOF'
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

# Create trusted hosts file
cat > /etc/opendkim/TrustedHosts << 'EOF'
127.0.0.1
localhost
192.168.0.1/24
10.0.0.1/8
172.16.0.1/12
*.YOUR_DOMAIN.com
EOF

# Create key table
echo "default._domainkey.YOUR_DOMAIN.com YOUR_DOMAIN.com:default:/etc/opendkim/keys/default.private" > /etc/opendkim/KeyTable

# Create signing table
echo "*@YOUR_DOMAIN.com default._domainkey.YOUR_DOMAIN.com" > /etc/opendkim/SigningTable

# Set permissions
chown -R opendkim:opendkim /etc/opendkim
chmod 600 /etc/opendkim/keys/default.private
```

### **Step 6: Enable Postfix Submission Port**

```bash
# Enable submission port (587) for SMTP
sed -i 's/#submission inet n       -       y       -       -       smtpd/submission inet n       -       y       -       -       smtpd/' /etc/postfix/master.cf
sed -i 's/#  -o syslog_name=postfix\/submission/  -o syslog_name=postfix\/submission/' /etc/postfix/master.cf
sed -i 's/#  -o smtpd_tls_security_level=encrypt/  -o smtpd_tls_security_level=may/' /etc/postfix/master.cf
sed -i 's/#  -o smtpd_sasl_auth_enable=yes/  -o smtpd_sasl_auth_enable=no/' /etc/postfix/master.cf
sed -i 's/#  -o smtpd_reject_unlisted_recipient=no/  -o smtpd_reject_unlisted_recipient=no/' /etc/postfix/master.cf

# Start services
systemctl enable postfix opendkim
systemctl restart postfix opendkim

# Verify port 587 is listening
ss -tlnp | grep :587
```

### **Step 7: Get DKIM Public Key**

```bash
# Display DKIM public key for DNS
cat /etc/opendkim/keys/default.txt
```

**Save this key - you'll add it to DNS later!**

---

## 🌐 **DNS Configuration (Cloudflare)**

### **Required DNS Records**

Add these records in your Cloudflare DNS dashboard:

| Type    | Name                 | Content                                                    | Proxy       |
| ------- | -------------------- | ---------------------------------------------------------- | ----------- |
| **A**   | `mail`               | `YOUR_SERVER_IP`                                           | ❌ DNS only |
| **MX**  | `@`                  | `10 mail.YOUR_DOMAIN.com`                                  | ❌ DNS only |
| **TXT** | `@`                  | `v=spf1 ip4:YOUR_SERVER_IP ip6:YOUR_IPV6 ~all`             | ❌ DNS only |
| **TXT** | `default._domainkey` | `v=DKIM1; k=rsa; p=YOUR_DKIM_KEY`                          | ❌ DNS only |
| **TXT** | `_dmarc`             | `v=DMARC1; p=quarantine; rua=mailto:admin@YOUR_DOMAIN.com` | ❌ DNS only |

### **PTR Records (Reverse DNS)**

**Contact your hosting provider** to set up PTR records:

- **IPv4 PTR:** `YOUR_SERVER_IP` → `mail.YOUR_DOMAIN.com`
- **IPv6 PTR:** `YOUR_IPV6` → `mail.YOUR_DOMAIN.com`

---

## 📡 **Node.js SMTP API Setup**

### **Step 8: Create API Server**

```bash
# Create project directory
mkdir -p /var/www/smtp-server
cd /var/www/smtp-server

# Initialize Node.js project
npm init -y

# Install dependencies
npm install nodemailer fastify @fastify/cors dotenv
```

### **Step 9: Create server.js**

```bash
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
  'YOUR_SERVER_IP',      // your server IP
  'YOUR_CLIENT_IP',      // your current IP
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
  }

  return allowed;
}

// IP whitelist middleware
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

// Verify SMTP connection
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
        from: emailData.from || process.env.SMTP_FROM || `noreply@YOUR_DOMAIN.com`,
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
    timestamp: new Date().toISOString()
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

    const messageId = `<${Date.now()}.${Math.random().toString(36).substr(2, 9)}@YOUR_DOMAIN.com>`;

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
```

### **Step 10: Create .env Configuration**

```bash
cat > .env << 'EOF'
# SMTP Configuration
SMTP_HOST=localhost
SMTP_PORT=587
SMTP_SECURE=false
SMTP_FROM=noreply@YOUR_DOMAIN.com

# Performance settings
SMTP_RATE_LIMIT=100
RETRY_DELAY=1000

# API Server
PORT=3000
HOST=0.0.0.0
EOF
```

---

## 🔄 **PM2 Process Management**

### **Step 11: Install and Configure PM2**

```bash
# Install PM2 globally
npm install -g pm2

# Create ecosystem configuration
cat > ecosystem.config.js << 'EOF'
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
pm2 start ecosystem.config.js

# Save PM2 configuration
pm2 save

# Set up PM2 to start on boot
pm2 startup
# Follow the command it shows you
```

---

## 🌐 **Cloudflare Tunnel Setup**

### **Step 12: Install Cloudflared**

```bash
# Install Cloudflared
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared.deb

# Verify installation
cloudflared --version
```

### **Step 13: Authenticate and Create Tunnel**

```bash
# Login to Cloudflare
cloudflared tunnel login
# Follow the browser authentication

# Create tunnel
cloudflared tunnel create smtp-YOUR_DOMAIN

# Create configuration
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml << 'EOF'
tunnel: TUNNEL_ID_FROM_PREVIOUS_COMMAND
credentials-file: ~/.cloudflared/TUNNEL_ID.json

ingress:
  - hostname: smtp.YOUR_DOMAIN.com
    service: http://localhost:3000
  - service: http_status:404
EOF

# Route DNS to tunnel
cloudflared tunnel route dns smtp-YOUR_DOMAIN smtp.YOUR_DOMAIN.com
```

### **Step 14: Add Tunnel to PM2**

```bash
# Update ecosystem.config.js
cat > ecosystem.config.js << 'EOF'
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
    },
    {
      name: 'cloudflare-tunnel',
      script: '/usr/local/bin/cloudflared',
      args: 'tunnel --config ~/.cloudflared/config.yml run smtp-YOUR_DOMAIN',
      cwd: '/root',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '500M'
    }
  ]
};
EOF

# Restart PM2 with tunnel
pm2 restart ecosystem.config.js
pm2 save
```

---

## 🔒 **Security Configuration**

### **Step 15: Configure Firewall**

```bash
# Block external SMTP access (force API-only)
ufw deny from any to any port 25
ufw deny from any to any port 587
ufw deny from any to any port 465

# Allow only localhost SMTP
ufw allow from 127.0.0.1 to any port 587

# Allow SSH and HTTPS
ufw allow 22
ufw allow 443

# Enable firewall
ufw enable
```

### **Step 16: Restrict Postfix**

```bash
# Configure Postfix to only accept local connections
postconf -e 'inet_interfaces = localhost'

# Restart Postfix
systemctl restart postfix
```

---

## 🧪 **Testing**

### **Test Email Sending**

```bash
# Test via public HTTPS API
curl -X POST https://smtp.YOUR_DOMAIN.com/send-email \
  -H "Content-Type: application/json" \
  -d '{
    "to": "test@gmail.com",
    "subject": "🚀 SMTP Server Test",
    "html": "<h1>Success!</h1><p>Your unlimited email server is working!</p>",
    "text": "Success! Your unlimited email server is working!"
  }'

# Check health
curl https://smtp.YOUR_DOMAIN.com/health

# Check queue status
curl https://smtp.YOUR_DOMAIN.com/queue-status
```

### **Monitor Logs**

```bash
# PM2 logs
pm2 logs

# Postfix logs
journalctl -u postfix -f

# Check queue
postqueue -p
```

---

## 🛠️ **Troubleshooting**

### **Common Issues**

#### **1. Emails Going to Spam**

- **Solution:** Add all DNS records (SPF, DKIM, DMARC)
- **Check:** Use mail-tester.com for deliverability score
- **Improve:** Build sender reputation gradually

#### **2. Port 25 Blocked by Hosting Provider**

- **Symptoms:** IPv4 timeout errors
- **Solution:** Contact hosting provider to unblock port 25
- **Alternative:** Use Gmail SMTP relay temporarily

#### **3. IPv6 Authentication Errors**

- **Symptoms:** Gmail IPv6 sending guidelines error
- **Solution:** Ensure IPv6 PTR record is set correctly
- **Check:** `dig -x YOUR_IPV6_ADDRESS`

#### **4. DKIM Signature Missing**

- **Check:** `systemctl status opendkim`
- **Fix:** Restart services in order: `opendkim` → `postfix`

#### **5. Node.js Can't Connect to Postfix**

- **Error:** `ECONNREFUSED 127.0.0.1:587`
- **Solution:** Ensure Postfix listens on localhost:587
- **Check:** `ss -tlnp | grep :587`

### **Debugging Commands**

```bash
# Check all services
systemctl status postfix opendkim
pm2 status

# Check DNS propagation
dig TXT YOUR_DOMAIN.com
dig TXT default._domainkey.YOUR_DOMAIN.com
dig MX YOUR_DOMAIN.com

# Check PTR records
dig -x YOUR_SERVER_IP
dig -x YOUR_IPV6

# Test SMTP connection
telnet localhost 587

# Check firewall
ufw status verbose

# Monitor access attempts
pm2 logs smtp-server | grep "Access attempt"
```

---

## 📊 **Final Result**

### **✅ What You Achieved:**

1. **Unlimited Email Sending** - No more 2000/day Gmail limit
2. **Professional Domain** - Send from `noreply@YOUR_DOMAIN.com`
3. **Public HTTPS API** - `https://smtp.YOUR_DOMAIN.com`
4. **Background Services** - Auto-restart with PM2
5. **Security Protection** - IP whitelisting, firewall
6. **Email Authentication** - DKIM, SPF, DMARC configured
7. **Rate Limiting** - Prevents abuse
8. **Queue Management** - Handles email processing

### **📡 API Endpoints:**

- **POST** `/send-email` - Send emails
- **GET** `/health` - Server status
- **GET** `/queue-status` - Email queue info

### **🔒 Security Features:**

- IP whitelisting (only authorized IPs can send)
- Firewall blocking direct SMTP access
- HTTPS-only public access
- Rate limiting and queue management

### **📈 Performance:**

- **Rate:** Up to 100 emails/minute (configurable)
- **Queue:** Automatic retry on failures
- **Monitoring:** PM2 dashboard and logs
- **Uptime:** Auto-restart on crashes

---

## 🚀 **Usage Examples**

### **Send Simple Email**

```bash
curl -X POST https://smtp.YOUR_DOMAIN.com/send-email \
  -H "Content-Type: application/json" \
  -d '{
    "to": "user@example.com",
    "subject": "Welcome!",
    "text": "Welcome to our service!"
  }'
```

### **Send HTML Email**

```bash
curl -X POST https://smtp.YOUR_DOMAIN.com/send-email \
  -H "Content-Type: application/json" \
  -d '{
    "to": "user@example.com",
    "subject": "Newsletter",
    "html": "<h1>Newsletter</h1><p>Your content here</p>",
    "text": "Newsletter - Your content here"
  }'
```

### **Integration Examples**

**Node.js:**

```javascript
const response = await fetch("https://smtp.YOUR_DOMAIN.com/send-email", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    to: "user@example.com",
    subject: "API Email",
    text: "Sent from Node.js",
  }),
});
```

**Python:**

```python
import requests

response = requests.post('https://smtp.YOUR_DOMAIN.com/send-email',
  json={
    'to': 'user@example.com',
    'subject': 'API Email',
    'text': 'Sent from Python'
  }
)
```

---

## 📚 **Maintenance**

### **Regular Tasks**

- Monitor PM2 services: `pm2 status`
- Check email queue: `postqueue -p`
- Review logs: `pm2 logs`
- Update system: `apt update && apt upgrade`

### **Adding IPs to Whitelist**

```bash
# Edit server.js
nano /var/www/smtp-server/server.js

# Add IP to allowedIPs array
# Restart PM2
pm2 restart smtp-server
```

### **Scaling**

- **Higher rate limits:** Increase `SMTP_RATE_LIMIT`
- **Multiple instances:** Increase PM2 instances
- **Load balancing:** Add multiple servers behind Cloudflare

---

**🎉 Congratulations! You now have a production-ready, unlimited email sending system!**

**Total setup time: ~30-45 minutes**
**Monthly cost: Server hosting only (no per-email fees)**
**Email limit: Unlimited ♾️**

---

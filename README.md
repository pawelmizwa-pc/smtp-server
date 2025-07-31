# SMTP Email Server

A Node.js Fastify backend for sending emails via SMTP using Gmail app passwords.

## Features

- Send single emails
- Send bulk emails to multiple recipients
- Send emails with attachments
- Gmail SMTP integration with app password authentication
- CORS support for frontend integration
- Health check endpoint

## Setup

1. Install dependencies:

```bash
npm install
```

2. Create a `.env` file in the root directory with the following variables:

```env
# Gmail SMTP Configuration
GMAIL_USER=your-email@gmail.com
GMAIL_APP_PASSWORD=your-app-password

# Server Configuration
PORT=3000
HOST=0.0.0.0
```

3. Get a Gmail App Password:
   - Go to your Google Account settings
   - Enable 2-factor authentication
   - Go to Security > App passwords
   - Generate a new app password for "Mail"
   - Use this password in your `.env` file

## Running the Server

Development mode (with auto-restart):

```bash
npm run dev
```

Production mode:

```bash
npm start
```

The server will start on `http://localhost:3000` by default.

## API Endpoints

### Health Check

```
GET /health
```

### Send Single Email

```
POST /send-email
Content-Type: application/json

{
  "to": "recipient@example.com",
  "subject": "Test Email",
  "text": "Plain text content",
  "html": "<h1>HTML content</h1>",
  "from": "optional-custom-sender@example.com"
}
```

### Send Bulk Emails

```
POST /send-bulk-email
Content-Type: application/json

{
  "recipients": ["user1@example.com", "user2@example.com"],
  "subject": "Bulk Email",
  "text": "Plain text content",
  "html": "<h1>HTML content</h1>",
  "from": "optional-custom-sender@example.com"
}
```

### Send Email with Attachments

```
POST /send-email-with-attachments
Content-Type: application/json

{
  "to": "recipient@example.com",
  "subject": "Email with Attachments",
  "text": "Please find the attached files",
  "attachments": [
    {
      "filename": "document.pdf",
      "content": "base64-encoded-content",
      "contentType": "application/pdf"
    }
  ]
}
```

## Response Format

### Success Response

```json
{
  "success": true,
  "messageId": "message-id",
  "message": "Email sent successfully"
}
```

### Error Response

```json
{
  "error": "Error message",
  "details": "Detailed error information"
}
```

## Environment Variables

| Variable             | Required | Description                                    |
| -------------------- | -------- | ---------------------------------------------- |
| `GMAIL_USER`         | Yes      | Your Gmail email address                       |
| `GMAIL_APP_PASSWORD` | Yes      | Gmail app password (not your regular password) |
| `PORT`               | No       | Server port (default: 3000)                    |
| `HOST`               | No       | Server host (default: 0.0.0.0)                 |

## Security Notes

- Never commit your `.env` file to version control
- Use Gmail app passwords, not regular passwords
- Consider rate limiting for production use
- Validate and sanitize all input data
- Use HTTPS in production

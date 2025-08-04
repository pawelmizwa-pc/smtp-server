// ====================
// Dependencies
// ====================
require("dotenv").config();
const fastify = require("fastify")({ logger: true });
const nodemailer = require("nodemailer");

// ====================
// Configuration
// ====================
const CONFIG = {
  // Server Configuration
  PORT: process.env.PORT || 3000,
  HOST: process.env.HOST || "0.0.0.0",
  
  // SMTP Configuration
  SMTP: {
    HOST: process.env.SMTP_HOST || "localhost",
    PORT: process.env.SMTP_PORT || 587,
    SECURE: process.env.SMTP_SECURE === "true",
    USER: process.env.SMTP_USER,
    PASSWORD: process.env.SMTP_PASSWORD,
    FROM: process.env.SMTP_FROM || process.env.SMTP_USER,
    REJECT_UNAUTHORIZED: process.env.SMTP_REJECT_UNAUTHORIZED !== "false",
  },
  
  // Rate Limiting Configuration
  RATE_LIMITING: {
    SMTP_RATE_LIMIT: parseInt(process.env.SMTP_RATE_LIMIT) || 1000, // milliseconds between emails
    RETRY_DELAY: parseInt(process.env.RETRY_DELAY) || 30000, // 30 seconds
  },
};

// ====================
// Application State
// ====================
const emailQueue = [];
let isProcessingQueue = false;
let lastEmailTime = 0;

// ====================
// Fastify Plugins
// ====================
fastify.register(require("@fastify/cors"), {
  origin: true,
});

// ====================
// SMTP Transporter Setup
// ====================
const transporter = nodemailer.createTransport({
  host: CONFIG.SMTP.HOST,
  port: CONFIG.SMTP.PORT,
  secure: CONFIG.SMTP.SECURE,
  auth: CONFIG.SMTP.USER
    ? {
        user: CONFIG.SMTP.USER,
        pass: CONFIG.SMTP.PASSWORD,
      }
    : false,
  tls: {
    rejectUnauthorized: CONFIG.SMTP.REJECT_UNAUTHORIZED,
  },
});

// Verify SMTP connection on startup
transporter.verify((error, success) => {
  if (error) {
    console.error("SMTP connection error:", error);
  } else {
    console.log("SMTP server is ready to send emails");
  }
});

// ====================
// Email Queue Functions
// ====================

/**
 * Process emails from the queue with rate limiting
 */
async function processEmailQueue() {
  if (isProcessingQueue || emailQueue.length === 0) {
    return;
  }

  isProcessingQueue = true;
  console.log(`Processing email queue. ${emailQueue.length} emails pending.`);

  while (emailQueue.length > 0) {
    const emailJob = emailQueue.shift();
    const now = Date.now();
    const timeSinceLastEmail = now - lastEmailTime;

    // Rate limiting: wait if needed
    if (timeSinceLastEmail < CONFIG.RATE_LIMITING.SMTP_RATE_LIMIT) {
      const waitTime = CONFIG.RATE_LIMITING.SMTP_RATE_LIMIT - timeSinceLastEmail;
      console.log(`Rate limiting: waiting ${waitTime}ms before next email`);
      await new Promise((resolve) => setTimeout(resolve, waitTime));
    }

    try {
      console.log(`Sending email ${emailJob.id} to ${emailJob.mailOptions.to}`);
      const info = await transporter.sendMail(emailJob.mailOptions);
      lastEmailTime = Date.now();

      emailJob.resolve({
        success: true,
        messageId: info.messageId,
        message: "Email sent successfully",
      });
    } catch (error) {
      console.error(`Error sending email ${emailJob.id}:`, error.message);

      // Handle rate limiting errors
      if (
        error.responseCode === 421 ||
        error.message.includes("421") ||
        error.message.includes("rate")
      ) {
        console.log("SMTP rate limit hit. Adding delay and retrying...");
        // Put the email back in queue with delay
        emailQueue.unshift(emailJob);
        await new Promise((resolve) =>
          setTimeout(resolve, CONFIG.RATE_LIMITING.RETRY_DELAY)
        );
        continue;
      }

      emailJob.reject({
        error: "Failed to send email",
        details: error.message,
        code: error.responseCode,
      });
    }
  }

  isProcessingQueue = false;
  console.log("Email queue processing completed.");
}

/**
 * Add email to queue for processing
 */
function queueEmail(mailOptions) {
  return new Promise((resolve, reject) => {
    const emailJob = {
      id: Date.now() + Math.random(),
      mailOptions,
      resolve,
      reject,
      timestamp: Date.now(),
    };

    emailQueue.push(emailJob);
    console.log(`Email queued. Queue length: ${emailQueue.length}`);

    // Start processing if not already running
    if (!isProcessingQueue) {
      processEmailQueue();
    }
  });
}

// ====================
// API Routes
// ====================

/**
 * Health check endpoint
 * GET /health
 */
fastify.get("/health", async (request, reply) => {
  return { 
    status: "OK", 
    message: "SMTP server is running" 
  };
});

/**
 * Queue status endpoint
 * GET /queue-status
 */
fastify.get("/queue-status", async (request, reply) => {
  return {
    queueLength: emailQueue.length,
    isProcessing: isProcessingQueue,
    lastEmailTime: lastEmailTime,
    rateLimitMs: CONFIG.RATE_LIMITING.SMTP_RATE_LIMIT,
  };
});

/**
 * Send single email endpoint
 * POST /send-email
 */
fastify.post("/send-email", async (request, reply) => {
  try {
    const { to, subject, text, html, from } = request.body;

    // Validation
    if (!to || !subject || (!text && !html)) {
      return reply.status(400).send({
        error: "Missing required fields: to, subject, and either text or html",
      });
    }

    // Email options
    const mailOptions = {
      from: from || CONFIG.SMTP.FROM,
      to: Array.isArray(to) ? to.join(", ") : to,
      subject: subject,
      text: text,
      html: html,
    };

    // Queue email instead of sending directly
    const result = await queueEmail(mailOptions);
    return result;
  } catch (error) {
    console.error("Error queueing email:", error);
    return reply.status(500).send({
      error: "Failed to queue email",
      details: error.message || error.details,
      code: error.code,
    });
  }
});

/**
 * Send bulk emails endpoint
 * POST /send-bulk-email
 */
fastify.post("/send-bulk-email", async (request, reply) => {
  try {
    const { recipients, subject, text, html, from } = request.body;

    // Validation
    if (!recipients || !Array.isArray(recipients) || recipients.length === 0) {
      return reply.status(400).send({
        error: "Recipients array is required and cannot be empty",
      });
    }

    if (!subject || (!text && !html)) {
      return reply.status(400).send({
        error: "Missing required fields: subject, and either text or html",
      });
    }

    const results = [];
    const errors = [];

    // Send emails concurrently with Promise.allSettled
    const emailPromises = recipients.map(async (recipient, index) => {
      try {
        const mailOptions = {
          from: from || CONFIG.SMTP.FROM,
          to: recipient,
          subject: subject,
          text: text,
          html: html,
        };

        const info = await transporter.sendMail(mailOptions);
        return {
          index,
          recipient,
          success: true,
          messageId: info.messageId,
        };
      } catch (error) {
        return {
          index,
          recipient,
          success: false,
          error: error.message,
        };
      }
    });

    const emailResults = await Promise.allSettled(emailPromises);

    emailResults.forEach((result, index) => {
      if (result.status === "fulfilled") {
        if (result.value.success) {
          results.push(result.value);
        } else {
          errors.push(result.value);
        }
      } else {
        errors.push({
          index,
          recipient: recipients[index],
          success: false,
          error: result.reason.message,
        });
      }
    });

    return {
      success: true,
      totalSent: results.length,
      totalErrors: errors.length,
      results: results,
      errors: errors,
    };
  } catch (error) {
    console.error("Error sending bulk emails:", error);
    return reply.status(500).send({
      error: "Failed to send bulk emails",
      details: error.message,
    });
  }
});

/**
 * Send email with attachments endpoint
 * POST /send-email-with-attachments
 */
fastify.post("/send-email-with-attachments", async (request, reply) => {
  try {
    const { to, subject, text, html, from, attachments } = request.body;

    // Validation
    if (!to || !subject || (!text && !html)) {
      return reply.status(400).send({
        error: "Missing required fields: to, subject, and either text or html",
      });
    }

    // Email options
    const mailOptions = {
      from: from || CONFIG.SMTP.FROM,
      to: Array.isArray(to) ? to.join(", ") : to,
      subject: subject,
      text: text,
      html: html,
    };

    // Add attachments if provided
    if (attachments && Array.isArray(attachments)) {
      mailOptions.attachments = attachments.map((attachment) => ({
        filename: attachment.filename,
        content: attachment.content,
        encoding: attachment.encoding || "base64",
        contentType: attachment.contentType,
      }));
    }

    // Send email
    const info = await transporter.sendMail(mailOptions);

    return {
      success: true,
      messageId: info.messageId,
      message: "Email with attachments sent successfully",
    };
  } catch (error) {
    console.error("Error sending email with attachments:", error);
    return reply.status(500).send({
      error: "Failed to send email with attachments",
      details: error.message,
    });
  }
});

// ====================
// Server Initialization
// ====================
const start = async () => {
  try {
    await fastify.listen({ 
      port: CONFIG.PORT, 
      host: CONFIG.HOST 
    });
    
    console.log(`Server running on http://${CONFIG.HOST}:${CONFIG.PORT}`);
  } catch (err) {
    console.error("Error starting server:", err);
    process.exit(1);
  }
};

// Start the server
start();
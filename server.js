require("dotenv").config();
const fastify = require("fastify")({ logger: true });
const nodemailer = require("nodemailer");

// Register CORS plugin
fastify.register(require("@fastify/cors"), {
  origin: true,
});

// Rate limiting for SMTP server
const emailQueue = [];
let isProcessingQueue = false;
const SMTP_RATE_LIMIT = process.env.SMTP_RATE_LIMIT || 1000; // milliseconds between emails (default 1 second)
let lastEmailTime = 0;

// SMTP Configuration - Self-hosted or custom SMTP
const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || "localhost",
  port: process.env.SMTP_PORT || 587,
  secure: process.env.SMTP_SECURE === "true", // true for 465, false for other ports
  auth: process.env.SMTP_USER
    ? {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASSWORD,
      }
    : false, // No auth for local server
  tls: {
    rejectUnauthorized: process.env.SMTP_REJECT_UNAUTHORIZED !== "false",
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

// Queue processing function
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
    if (timeSinceLastEmail < SMTP_RATE_LIMIT) {
      const waitTime = SMTP_RATE_LIMIT - timeSinceLastEmail;
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
          setTimeout(resolve, parseInt(process.env.RETRY_DELAY) || 30000)
        ); // configurable delay
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

// Queue email function
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

// Health check endpoint
fastify.get("/health", async (request, reply) => {
  return { status: "OK", message: "SMTP server is running" };
});

// Queue status endpoint
fastify.get("/queue-status", async (request, reply) => {
  return {
    queueLength: emailQueue.length,
    isProcessing: isProcessingQueue,
    lastEmailTime: lastEmailTime,
    rateLimitMs: SMTP_RATE_LIMIT,
  };
});

// Send email endpoint
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
      from: from || process.env.SMTP_FROM || process.env.SMTP_USER,
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

// Send bulk emails endpoint
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
          from: from || process.env.SMTP_FROM || process.env.SMTP_USER,
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

// Send email with attachments endpoint
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
      from: from || process.env.SMTP_FROM || process.env.SMTP_USER,
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

// Start the server
const start = async () => {
  try {
    const port = process.env.PORT || 3000;
    const host = process.env.HOST || "0.0.0.0";

    await fastify.listen({ port, host });
    console.log(`Server running on http://${host}:${port}`);
  } catch (err) {
    console.error("Error starting server:", err);
    process.exit(1);
  }
};

start();

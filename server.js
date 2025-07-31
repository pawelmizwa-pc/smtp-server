require("dotenv").config();
const fastify = require("fastify")({ logger: true });
const nodemailer = require("nodemailer");

// Register CORS plugin
fastify.register(require("@fastify/cors"), {
  origin: true,
});

// SMTP Configuration
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: process.env.GMAIL_USER,
    pass: process.env.GMAIL_APP_PASSWORD,
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

// Health check endpoint
fastify.get("/health", async (request, reply) => {
  return { status: "OK", message: "SMTP server is running" };
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
      from: from || process.env.GMAIL_USER,
      to: Array.isArray(to) ? to.join(", ") : to,
      subject: subject,
      text: text,
      html: html,
    };

    // Send email
    const info = await transporter.sendMail(mailOptions);

    return {
      success: true,
      messageId: info.messageId,
      message: "Email sent successfully",
    };
  } catch (error) {
    console.error("Error sending email:", error);
    return reply.status(500).send({
      error: "Failed to send email",
      details: error.message,
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
          from: from || process.env.GMAIL_USER,
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
      from: from || process.env.GMAIL_USER,
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

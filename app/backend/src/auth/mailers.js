// How a one-time code reaches an e-mail inbox. Same shape as the phone providers in providers.js:
// { name, exposeCode, send(email, code) }, so the OTP service does not care which channel it serves.
//
//   console  development: prints the code in the server log and hands it back as `devCode` so the app can fill it in.
//            Refuses to run in production.
//   memory   tests: remembers the messages it was asked to send.
//   smtp     real e-mail through any SMTP service (Brevo, Resend, Amazon SES, Gmail with an app password, ...).
//            Settings:
//              SMTP_HOST   e.g. smtp-relay.brevo.com, smtp.resend.com, email-smtp.ap-south-1.amazonaws.com
//              SMTP_PORT   587 (STARTTLS, default) or 465 (TLS from the first byte)
//              SMTP_USER / SMTP_PASS   the service's SMTP login (keep out of git)
//              MAIL_FROM   the sender, e.g. FOREST <noreply@forestapp.in>. Its domain must have SPF and DKIM set up at
//                          the service, or inboxes will put the code in spam.
//            Written from nodemailer's documented API and tested with a fake transport; send a code to your own address
//            before relying on it.

const { maskEmail } = require('./email');

const SUBJECT = (code) => `${code} is your FOREST code`;
const TEXT = (code) => `Your FOREST sign-up code is ${code}.\n\nIt works for 5 minutes. If you did not ask for it, ignore this e-mail: nobody can use your address without it.\n`;
const HTML = (code) => `<div style="font-family:Arial,sans-serif;max-width:420px;margin:auto;padding:24px;color:#1b2b22">
<p style="font-size:15px;margin:0 0 12px">Your FOREST sign-up code is</p>
<p style="font-size:34px;letter-spacing:6px;font-weight:700;margin:0 0 16px;color:#1d6b49">${code}</p>
<p style="font-size:13px;color:#5b6b62;margin:0">It works for 5 minutes. If you did not ask for it, ignore this e-mail: nobody can use your address without it.</p></div>`;

/**
 * @param {string} name  console | memory | smtp
 * @param {object} [o]
 * @param {boolean} [o.production]  refuses the dev-only providers
 * @param {object} [o.env]          where smtp reads its settings (default process.env)
 * @param {Function} [o.transportFactory]  (options) => { sendMail(message) }; default nodemailer, tests pass a fake
 */
function createMailer(name, { production = false, env = process.env, transportFactory = null } = {}) {
  switch (name) {
    case 'console':
      if (production) throw new Error('MAIL_PROVIDER=console cannot be used in production: it would print codes and return them to callers');
      return {
        name: 'console',
        exposeCode: true,
        async send(email, code) { console.log(`[OTP] code for ${email}: ${code}`); }
      };
    case 'memory': {
      const sent = [];
      return {
        name: 'memory',
        exposeCode: false,
        sent,
        last: (email) => [...sent].reverse().find((s) => s.email === email),
        async send(email, code) { sent.push({ email, code }); }
      };
    }
    case 'smtp': {
      const { SMTP_HOST: host, SMTP_USER: user, SMTP_PASS: pass, MAIL_FROM: from } = env;
      if (!host || !user || !pass || !from) throw new Error('MAIL_PROVIDER=smtp needs SMTP_HOST, SMTP_USER, SMTP_PASS and MAIL_FROM');
      const port = Number(env.SMTP_PORT) || 587;
      const options = {
        host, port, secure: port === 465, auth: { user, pass },
        connectionTimeout: 10000, greetingTimeout: 10000, socketTimeout: 15000
      };
      const factory = transportFactory || ((o) => require('nodemailer').createTransport(o));
      const transport = factory(options);
      return {
        name: 'smtp',
        exposeCode: false, // a real provider must never hand the code back to the caller
        async send(email, code) {
          try {
            await transport.sendMail({ from, to: email, subject: SUBJECT(code), text: TEXT(code), html: HTML(code) });
          } catch (err) {
            // Say what went wrong, but never the code or the full address.
            throw new Error(`smtp refused the message for ${maskEmail(email)} (${err.responseCode || err.code || 'error'}: ${String(err.message).replace(/\d{6}/g, '******')})`);
          }
        }
      };
    }
    default:
      throw new Error(`Unknown MAIL_PROVIDER "${name}". Available: console (dev), smtp.`);
  }
}

module.exports = { createMailer };

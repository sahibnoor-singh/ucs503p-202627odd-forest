// How a one-time code reaches a phone. The rest of the server only knows { name, send(phone, code) }, so
// switching provider later (Firebase for the alpha, then WhatsApp + MSG91 SMS) touches only this file.
//
//   console  development: prints the code in the server log and hands it back to the caller as `devCode`
//            so the app can fill it in. Refuses to run in production.
//   memory   tests: remembers the codes it was asked to send.
//
//   msg91    real SMS through MSG91's OTP API (India, DLT-registered sender and template required).
//            PLACEHOLDER: written from MSG91's public docs and unit-tested with a fake HTTP layer, but never run
//            against the live service because it needs your account. Before relying on it, send a code to your own
//            number and check the log line this file prints on failure. Settings (all required):
//              MSG91_AUTHKEY      the account's auth key (keep it out of git)
//              MSG91_TEMPLATE_ID  the approved OTP template; it must contain the ##OTP## variable
//
// Not built yet: firebase, whatsapp.

/** `+919876543210` -> `+91*******210`. Phone numbers are personal data: logs never get the full number. */
const mask = (phone) => String(phone).replace(/^(\+?\d{2})\d+(\d{3})$/, (m, a, b) => `${a}${'*'.repeat(m.length - a.length - b.length)}${b}`);

/**
 * @param {string} name  console | memory | msg91
 * @param {object} [o]
 * @param {boolean} [o.production]  refuses the dev-only providers
 * @param {object} [o.env]          where msg91 reads its settings (default process.env)
 * @param {Function} [o.fetchImpl]  HTTP function (default global fetch); tests pass a fake
 */
function createProvider(name, { production = false, env = process.env, fetchImpl = fetch } = {}) {
  switch (name) {
    case 'console':
      if (production) throw new Error('OTP_PROVIDER=console cannot be used in production: it would print codes and return them to callers');
      return {
        name: 'console',
        exposeCode: true,
        async send(phone, code) { console.log(`[OTP] code for ${phone}: ${code}`); }
      };
    case 'memory': {
      const sent = [];
      return {
        name: 'memory',
        exposeCode: false,
        sent,
        last: (phone) => [...sent].reverse().find((s) => s.phone === phone),
        async send(phone, code) { sent.push({ phone, code }); }
      };
    }
    case 'msg91': {
      const authkey = env.MSG91_AUTHKEY;
      const templateId = env.MSG91_TEMPLATE_ID;
      if (!authkey || !templateId) throw new Error('OTP_PROVIDER=msg91 needs MSG91_AUTHKEY and MSG91_TEMPLATE_ID');
      return {
        name: 'msg91',
        exposeCode: false, // a real provider must never hand the code back to the caller
        async send(phone, code) {
          // MSG91 wants the number without the "+", e.g. 919876543210.
          const mobile = String(phone).replace(/^\+/, '');
          const res = await fetchImpl('https://control.msg91.com/api/v5/otp', {
            method: 'POST',
            headers: { 'content-type': 'application/json', authkey },
            body: JSON.stringify({ template_id: templateId, mobile, otp: code }),
            signal: AbortSignal.timeout(10000)
          });
          let body = null;
          try { body = await res.json(); } catch { /* not JSON */ }
          if (!res.ok || !body || body.type !== 'success') {
            // Say what went wrong, but never the code or the full number.
            throw new Error(`msg91 refused the message for ${mask(phone)} (HTTP ${res.status}${body && body.message ? `: ${body.message}` : ''})`);
          }
        }
      };
    }
    default:
      throw new Error(`Unknown OTP_PROVIDER "${name}". Available: console (dev), msg91.`);
  }
}

module.exports = { createProvider, mask };

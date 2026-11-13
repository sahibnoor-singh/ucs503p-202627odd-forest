// Rules for the e-mail address used to sign up. An e-mail is free to make, so unlike a phone number it proves
// little by itself; these rules close the cheap ways to get many accounts out of one mailbox.
//   - one canonical form per mailbox: Gmail ignores dots and "+tags", so a.b+1@gmail.com and ab@gmail.com are one account
//   - "+tags" on other providers are refused (we cannot know they all ignore them), so one mailbox cannot be many
//   - throw-away inbox services are refused
//   - optionally only some domains may sign up (SIGNUP_EMAIL_DOMAINS, e.g. a campus domain for a pilot)

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const GMAIL = new Set(['gmail.com', 'googlemail.com']);

// A short list of the common throw-away services. It cannot be complete: add more with SIGNUP_BLOCKED_EMAIL_DOMAINS.
const DISPOSABLE = new Set([
  'mailinator.com', 'guerrillamail.com', 'guerrillamail.net', 'guerrillamail.org', 'sharklasers.com', 'grr.la',
  '10minutemail.com', '10minutemail.net', 'tempmail.com', 'temp-mail.org', 'temp-mail.io', 'tempmail.net',
  'throwawaymail.com', 'yopmail.com', 'yopmail.net', 'trashmail.com', 'trashmail.net', 'getnada.com', 'nada.email',
  'dispostable.com', 'maildrop.cc', 'fakeinbox.com', 'mailnesia.com', 'mintemail.com', 'mohmal.com',
  'emailondeck.com', 'burnermail.io', 'spamgourmet.com', 'tempail.com', 'tmpmail.org', 'mytemp.email',
  'moakt.com', 'discard.email', 'mailcatch.com', 'inboxkitten.com', 'tempinbox.com', 'mail.tm', 'dropmail.me'
]);

const typedOf = (raw) => String(raw === undefined || raw === null ? '' : raw).trim().toLowerCase();
const domainOf = (email) => email.slice(email.lastIndexOf('@') + 1);
const inList = (domain, list) => list.some((d) => domain === d || domain.endsWith(`.${d}`));
const clean = (list) => list.map((d) => String(d).trim().toLowerCase()).filter(Boolean);

/** The one form of this address we compare and store, or null when it is not an e-mail address at all. */
function normalizeEmail(raw) {
  const email = typedOf(raw);
  if (email.length > 254 || !EMAIL.test(email) || email.split('@').length !== 2) return null;
  let [local, domain] = email.split('@');
  if (GMAIL.has(domain)) {
    local = local.split('+')[0].replace(/\./g, '');
    domain = 'gmail.com';
    if (!local) return null;
  }
  return `${local}@${domain}`;
}

/**
 * Why this address cannot be used to sign up, in words for the person, or null when it can.
 * @param {string} email  as typed
 * @param {object} [o]
 * @param {string[]} [o.allowedDomains]  when not empty, only these domains (and their subdomains)
 * @param {string[]} [o.blockedDomains]  refused on top of the built-in throw-away list
 */
function emailProblem(email, { allowedDomains = [], blockedDomains = [] } = {}) {
  const typed = typedOf(email);
  const canonical = normalizeEmail(typed);
  if (!canonical) return 'Enter a valid e-mail address';
  const domain = domainOf(canonical);
  if (!GMAIL.has(domainOf(typed)) && typed.split('@')[0].includes('+')) return 'Use your plain e-mail address, without a + in it';
  const allowed = clean(allowedDomains);
  if (allowed.length && !inList(domain, allowed)) return `Sign-up is open only to ${allowed.map((d) => `@${d}`).join(', ')} addresses for now`;
  if (DISPOSABLE.has(domain) || inList(domain, clean(blockedDomains))) return 'Temporary e-mail addresses cannot be used. Use your own e-mail';
  return null;
}

/** `riya.kapoor@gmail.com` -> `r***@gmail.com`. Addresses are personal data: logs never get the full one. */
const maskEmail = (email) => String(email).replace(/^(.).*(@.*)$/, '$1***$2');

module.exports = { normalizeEmail, emailProblem, maskEmail, EMAIL };

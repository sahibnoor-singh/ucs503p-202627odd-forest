// Phone numbers are stored in E.164 (+<country><number>). India-first: a bare 10-digit mobile number
// (starting 6-9) gets the default country code.

function normalizePhone(input, defaultCountry = '+91') {
  if (typeof input !== 'string') return null;
  const cleaned = input.trim().replace(/[\s\-().]/g, '');
  if (/^\+[1-9]\d{7,14}$/.test(cleaned)) return cleaned;
  if (/^0?[6-9]\d{9}$/.test(cleaned) && defaultCountry === '+91') return `+91${cleaned.slice(-10)}`;
  if (/^\d{8,15}$/.test(cleaned) && defaultCountry !== '+91') return `${defaultCountry}${cleaned}`;
  return null;
}

module.exports = { normalizePhone };

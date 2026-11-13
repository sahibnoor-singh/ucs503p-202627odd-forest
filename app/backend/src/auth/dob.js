// Date of birth as YYYY-MM-DD, with an age gate. The minimum age is 18 for the alpha and beta (India's DPDP Act
// treats under-18s as children needing verifiable parental consent, which we don't have yet).

/** @returns { age } or { error } */
function checkDob(input, { minAge = 18, today = new Date() } = {}) {
  if (typeof input !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(input)) return { error: 'Enter your date of birth as YYYY-MM-DD' };
  const [y, m, d] = input.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  if (date.getUTCFullYear() !== y || date.getUTCMonth() !== m - 1 || date.getUTCDate() !== d) {
    return { error: 'That is not a real date' };
  }
  const ty = today.getUTCFullYear(), tm = today.getUTCMonth(), td = today.getUTCDate();
  let age = ty - y;
  if (tm < m - 1 || (tm === m - 1 && td < d)) age--; // birthday hasn't happened yet this year
  if (age < 0) return { error: 'Date of birth is in the future' };
  if (age > 120) return { error: 'That is not a real date' };
  if (age < minAge) return { error: `You must be at least ${minAge} to use FOREST`, tooYoung: true };
  return { age };
}

module.exports = { checkDob };

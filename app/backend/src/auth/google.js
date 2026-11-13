// "Continue with Google": the app signs the person in with Google on the phone and sends us the ID token Google
// gave it. We check Google's signature on it (keys are fetched from Google and cached by the library) and that it was
// issued for OUR app (the audience), then trust the e-mail inside it, which Google has already verified.
//
// Settings: GOOGLE_CLIENT_IDS = the OAuth "Web application" client id (and any others the app may use), comma separated.
// The app asks Google for a token with that Web client id as its audience, so the first id in the list is the one the
// app is told about (GET /api/auth/config -> googleClientId).
//
// The rest of the server only knows { verify(idToken) -> { sub, email, emailVerified, name } }; tests pass a fake.

/**
 * @param {object} o
 * @param {string[]} o.clientIds  accepted audiences
 * @param {Function} [o.clientFactory]  () => { verifyIdToken({idToken, audience}) }; default google-auth-library
 * @returns {{ verify(idToken: string): Promise<{sub:string,email:string,emailVerified:boolean,name:string}> }|null}  null when no client id is set
 */
function createGoogleVerifier({ clientIds, clientFactory = null }) {
  const audience = (clientIds || []).map((c) => String(c).trim()).filter(Boolean);
  if (!audience.length) return null;
  const client = (clientFactory || (() => new (require('google-auth-library').OAuth2Client)()))();
  return {
    async verify(idToken) {
      const ticket = await client.verifyIdToken({ idToken, audience });
      const p = ticket.getPayload() || {};
      if (!p.sub) throw new Error('Google token has no subject');
      return { sub: String(p.sub), email: String(p.email || ''), emailVerified: p.email_verified === true, name: String(p.name || '') };
    }
  };
}

module.exports = { createGoogleVerifier };

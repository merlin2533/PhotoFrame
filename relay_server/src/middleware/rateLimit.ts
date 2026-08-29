import rateLimit from 'express-rate-limit';

/** Applied to /api/v1/auth/* - login/register brute-force protection. */
export const authRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'too many auth attempts, please try again later' },
});

/** Applied to /api/v1/pairing/create-code - prevents code-enumeration/spam. */
export const pairingCreateRateLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  limit: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'too many pairing-code requests, please try again later' },
});

/** Applied to /api/v1/pairing/redeem - throttles code-guessing. */
export const pairingRedeemRateLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'too many redeem attempts, please try again later' },
});

/** Applied to /api/v1/frames/:id/recover - recovery is a sensitive, rate-limited flow. */
export const recoveryRateLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  limit: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'too many recovery attempts, please try again later' },
});

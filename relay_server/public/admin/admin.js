const API_BASE = '/api/v1/admin';

async function handleResponse(res) {
  if (!res.ok) {
    let message = `Request failed (${res.status})`;
    try {
      const body = await res.json();
      if (body.error) message = body.error;
    } catch {
      // ignore
    }
    const err = new Error(message);
    err.status = res.status;
    throw err;
  }
  return res.json();
}

window.AdminApi = {
  async login(username, password) {
    const res = await fetch(`${API_BASE}/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password }),
    });
    const data = await handleResponse(res);
    return data.token;
  },

  async get(token, pathSuffix) {
    const res = await fetch(`${API_BASE}${pathSuffix}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    return handleResponse(res);
  },

  async post(token, pathSuffix, body) {
    const res = await fetch(`${API_BASE}${pathSuffix}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify(body ?? {}),
    });
    return handleResponse(res);
  },

  async del(token, pathSuffix) {
    const res = await fetch(`${API_BASE}${pathSuffix}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    });
    return handleResponse(res);
  },
};

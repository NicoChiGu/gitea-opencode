export class GiteaClient {
  constructor({ apiUrl, owner, repo, token, fetchImpl = fetch }) {
    this.apiUrl = stripTrailingSlash(apiUrl);
    this.owner = owner;
    this.repo = repo;
    this.token = token;
    this.fetch = fetchImpl;
  }

  async getRepo() {
    return this.request("GET", `/repos/${this.owner}/${this.repo}`);
  }

  async getIssue(index) {
    return this.request("GET", `/repos/${this.owner}/${this.repo}/issues/${index}`);
  }

  async listIssueComments(index) {
    return this.request("GET", `/repos/${this.owner}/${this.repo}/issues/${index}/comments`);
  }

  async createIssueComment(index, body) {
    return this.request("POST", `/repos/${this.owner}/${this.repo}/issues/${index}/comments`, { body });
  }

  async getPull(index) {
    return this.request("GET", `/repos/${this.owner}/${this.repo}/pulls/${index}`);
  }

  async getPullDiff(index) {
    return this.requestText("GET", `/repos/${this.owner}/${this.repo}/pulls/${index}.diff`);
  }

  async getCollaboratorPermission(username) {
    return this.request("GET", `/repos/${this.owner}/${this.repo}/collaborators/${encodeURIComponent(username)}/permission`);
  }

  async createPullRequest({ title, body, head, base }) {
    return this.request("POST", `/repos/${this.owner}/${this.repo}/pulls`, {
      title,
      body,
      head,
      base,
    });
  }

  async request(method, path, body) {
    const response = await this.fetch(`${this.apiUrl}${path}`, this.options(method, body));
    if (!response.ok) {
      throw new GiteaApiError(method, path, response.status, await safeText(response));
    }
    if (response.status === 204) return null;
    return response.json();
  }

  async requestText(method, path) {
    const response = await this.fetch(`${this.apiUrl}${path}`, this.options(method));
    if (!response.ok) {
      throw new GiteaApiError(method, path, response.status, await safeText(response));
    }
    return response.text();
  }

  options(method, body) {
    return {
      method,
      headers: {
        Authorization: `token ${this.token}`,
        "Content-Type": "application/json",
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    };
  }
}

export class GiteaApiError extends Error {
  constructor(method, path, status, body) {
    super(`Gitea API ${method} ${path} failed with ${status}: ${body}`);
    this.name = "GiteaApiError";
    this.status = status;
    this.path = path;
    this.body = body;
  }
}

export function hasWritePermission(permission) {
  if (!permission) return false;

  const value = String(permission.permission || permission.role_name || permission.access_mode || "").toLowerCase();
  if (["write", "admin", "owner"].includes(value)) return true;

  const units = permission.units || permission.user_permissions || permission.permissions || {};
  return Boolean(
    units.admin ||
      units.write ||
      units.push ||
      units.code === "write" ||
      units.contents === "write" ||
      units.pull_requests === "write" ||
      units["pull-requests"] === "write"
  );
}

async function safeText(response) {
  try {
    return await response.text();
  } catch {
    return "";
  }
}

function stripTrailingSlash(value) {
  return String(value || "").replace(/\/+$/, "");
}

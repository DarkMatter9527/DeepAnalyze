// API 配置：
// - 显式 NEXT_PUBLIC_BACKEND_URL / NEXT_PUBLIC_FILE_SERVER_BASE 优先（如云上单独映射了 8200/8100）。
// - 否则在浏览器内走「当前站点 + Next rewrites」代理到本机 8200/8100（见 next.config.mjs），
//   适用于仅映射前端端口（如 SeeTacloud 6008→8443）时，避免请求打到打不开的 :8200。
// - SSR 仍直连 localhost，与 dev 服务器同机即可。

const ENV_BACKEND = process.env.NEXT_PUBLIC_BACKEND_URL;
const ENV_FILE = process.env.NEXT_PUBLIC_FILE_SERVER_BASE;

export function getBackendBaseUrl(): string {
  if (ENV_BACKEND) return ENV_BACKEND;
  if (typeof window !== "undefined") {
    return `${window.location.origin}/deepanalyze-backend`;
  }
  return "http://127.0.0.1:8200";
}

export function getFileServerBase(): string {
  if (ENV_FILE) return ENV_FILE;
  if (typeof window !== "undefined") {
    return `${window.location.origin}/deepanalyze-files`;
  }
  return "http://127.0.0.1:8100";
}

export const API_CONFIG = {
  get BACKEND_BASE_URL() {
    return getBackendBaseUrl();
  },
  get FILE_SERVER_BASE() {
    return getFileServerBase();
  },
  AI_API_BASE_URL:
    process.env.NEXT_PUBLIC_AI_API_URL || "http://localhost:8000",
  WEBSOCKET_URL: process.env.NEXT_PUBLIC_WEBSOCKET_URL || "ws://localhost:8001",
  ENDPOINTS: {
    CHAT_COMPLETIONS: "/chat/completions",
    WORKSPACE_FILES: "/workspace/files",
    WORKSPACE_TREE: "/workspace/tree",
    WORKSPACE_UPLOAD: "/workspace/upload",
    WORKSPACE_CLEAR: "/workspace/clear",
    WORKSPACE_DELETE_FILE: "/workspace/file",
    WORKSPACE_UPLOAD_TO: "/workspace/upload-to",
    WORKSPACE_DELETE_DIR: "/workspace/dir",
    EXECUTE_CODE: "/execute",
    EXPORT_REPORT: "/export/report",
  },
};

export const buildApiUrl = (
  endpoint: string,
  baseUrl: string = getBackendBaseUrl()
) => `${baseUrl}${endpoint}`;

/** 每次读取时按当前页 hostname 解析（勿在模块顶层缓存为常量） */
export const API_URLS = {
  get WORKSPACE_FILES() {
    return buildApiUrl(API_CONFIG.ENDPOINTS.WORKSPACE_FILES);
  },
  get WORKSPACE_TREE() {
    return buildApiUrl(API_CONFIG.ENDPOINTS.WORKSPACE_TREE);
  },
  get WORKSPACE_UPLOAD() {
    return buildApiUrl(API_CONFIG.ENDPOINTS.WORKSPACE_UPLOAD);
  },
  get WORKSPACE_CLEAR() {
    return buildApiUrl(API_CONFIG.ENDPOINTS.WORKSPACE_CLEAR);
  },
  get WORKSPACE_DELETE_FILE() {
    return buildApiUrl(API_CONFIG.ENDPOINTS.WORKSPACE_DELETE_FILE);
  },
  get WORKSPACE_UPLOAD_TO() {
    return buildApiUrl(API_CONFIG.ENDPOINTS.WORKSPACE_UPLOAD_TO);
  },
  get WORKSPACE_DELETE_DIR() {
    return buildApiUrl(API_CONFIG.ENDPOINTS.WORKSPACE_DELETE_DIR);
  },
  get EXECUTE_CODE() {
    return buildApiUrl(API_CONFIG.ENDPOINTS.EXECUTE_CODE);
  },
  get EXPORT_REPORT() {
    return buildApiUrl(API_CONFIG.ENDPOINTS.EXPORT_REPORT);
  },
  get CHAT_COMPLETIONS() {
    return buildApiUrl(API_CONFIG.ENDPOINTS.CHAT_COMPLETIONS);
  },
};

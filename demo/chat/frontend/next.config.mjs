import path from 'path'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

/** @type {import('next').NextConfig} */
const nextConfig = {
  // 远程域名打开 dev（如 AutoDL / SeeTacloud）时避免 HMR、/_next 资源被拦。
  // 面板将 127.0.0.1:6008 映射到 https://<子域>.bjb2.seetacloud.com:8443 时，需允许该来源（Next 支持 *. 前缀通配一层子域，见官方 allowedDevOrigins）。
  // 其它域名用逗号分隔追加：NEXT_ALLOWED_DEV_ORIGINS=host1,host2 ./start.sh
  allowedDevOrigins: [
    '*.bjb2.seetacloud.com',
    ...(process.env.NEXT_ALLOWED_DEV_ORIGINS
      ? process.env.NEXT_ALLOWED_DEV_ORIGINS.split(',').map((s) => s.trim()).filter(Boolean)
      : []),
  ],
  turbopack: {
    root: __dirname,
    resolveAlias: {
      fs: { browser: './lib/node-stub.js' },
      net: { browser: './lib/node-stub.js' },
      tls: { browser: './lib/node-stub.js' },
    },
  },
  typescript: {
    ignoreBuildErrors: true,
  },
  images: {
    unoptimized: true,
  },
  // 浏览器只映射了前端端口（如 6008→8443）时，不能直接访问容器内 8200/8100；
  // 经 Next 同源路径转发到本机后端，避免 Failed to fetch（仍可用 NEXT_PUBLIC_BACKEND_URL 覆盖直连）。
  async rewrites() {
    return [
      {
        source: '/deepanalyze-backend/:path*',
        destination: 'http://127.0.0.1:8200/:path*',
      },
      {
        source: '/deepanalyze-files/:path*',
        destination: 'http://127.0.0.1:8100/:path*',
      },
    ]
  },
  webpack: (config, { isServer }) => {
    if (!isServer) {
      config.resolve.fallback = {
        ...config.resolve.fallback,
        fs: false,
        net: false,
        tls: false,
      }
    }
    return config
  },
}

export default nextConfig

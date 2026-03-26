<div align="center">

  <a href="https://t.me/aitorroma">
    <img src="https://tva1.sinaimg.cn/large/008i3skNgy1gq8sv4q7cqj303k03kweo.jpg" alt="Aitor Roma" />
  </a>

  <br>

  [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/J3J64AN17)

  <br>

  <a href="https://t.me/aitorroma">
    <img src="https://img.shields.io/badge/Telegram-informational?style=for-the-badge&logo=telegram&logoColor=white" alt="Telegram Badge"/>
  </a>
</div>

# Paperclip for Coolify

Deploy Paperclip on Coolify from a public Git repository using the Docker Compose build pack, with HTTPS handled by Coolify's reverse proxy.

## Coolify Setup

1. Create a new resource from `Public Repository`.
2. Select `Docker Compose` as the build pack.
3. Set `Base Directory` to `/`.
4. Set `Docker Compose Location` to `docker-compose.yaml`.
5. Assign a domain to the `server` service so Coolify can provision HTTPS.

## Optional Environment Variables

- `PAPERCLIP_REF`: branch, tag, or commit to build from the upstream Paperclip repository. Default: `main`
- `PAPERCLIP_REPOSITORY`: upstream Paperclip Git URL. Default: `https://github.com/paperclipai/paperclip.git`
- `POSTGRES_USER`: database username. Default: `paperclip`
- `POSTGRES_DB`: database name. Default: `paperclip`
- `POSTGRES_PASSWORD`: set manually only if you do not want Coolify to auto-generate it
- `BETTER_AUTH_SECRET`: set manually only if you do not want Coolify to auto-generate it

## Notes

- The app is exposed internally on port `3100`.
- HTTPS termination is expected to happen in Coolify, not inside the container.
- `PAPERCLIP_PUBLIC_URL` is taken from Coolify's generated service URL.

# Supabase Docker

This is a minimal Docker Compose setup for self-hosting Supabase. Follow the steps [here](https://supabase.com/docs/guides/hosting/docker) to get started.

Alias: Restart Docker Compose Service

alias dreup='f() { docker compose down "$1" && docker compose up -d "$1"; }; f'
source ~/.bashrc

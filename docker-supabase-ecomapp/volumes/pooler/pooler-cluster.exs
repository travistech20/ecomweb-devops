{:ok, _} = Application.ensure_all_started(:supavisor)

{:ok, version} =
  case Supavisor.Repo.query!("select version()") do
    %{rows: [[ver]]} -> Supavisor.Helpers.parse_pg_version(ver)
    _ -> nil
  end

tenant_id = System.get_env("POOLER_TENANT_ID")
postgres_password = System.get_env("POSTGRES_PASSWORD")
pool_size = System.get_env("POOLER_DEFAULT_POOL_SIZE")
pool_mode = System.get_env("POOLER_POOL_MODE")
max_clients = System.get_env("POOLER_MAX_CLIENT_CONN")

# Create master tenant
master_params = %{
  "external_id" => "#{tenant_id}_master",
  "db_host" => "db",
  "db_port" => System.get_env("POSTGRES_PORT"),
  "db_database" => System.get_env("POSTGRES_DB"),
  "require_user" => false,
  "auth_query" => "SELECT * FROM pgbouncer.get_auth($1)",
  "default_max_clients" => max_clients,
  "default_pool_size" => pool_size,
  "default_parameter_status" => %{"server_version" => version},
  "users" => [%{
    "db_user" => "pgbouncer",
    "db_password" => postgres_password,
    "mode_type" => pool_mode,
    "pool_size" => pool_size,
    "is_manager" => true
  }]
}

# Create replica 1 tenant
replica1_params = %{
  "external_id" => "#{tenant_id}_replica1",
  "db_host" => "db-replica-1",  # Change to your replica hostname
  "db_port" => System.get_env("POSTGRES_PORT"),
  "db_database" => System.get_env("POSTGRES_DB"),
  "require_user" => false,
  "auth_query" => "SELECT * FROM pgbouncer.get_auth($1)",
  "default_max_clients" => max_clients,
  "default_pool_size" => pool_size,
  "default_parameter_status" => %{"server_version" => version},
  "users" => [%{
    "db_user" => "pgbouncer",
    "db_password" => postgres_password,
    "mode_type" => pool_mode,
    "pool_size" => pool_size,
    "is_manager" => true
  }]
}

# Create or update tenants
case Supavisor.Tenants.get_tenant_by_external_id(master_params["external_id"]) do
  nil ->
    {:ok, _} = Supavisor.Tenants.create_tenant(master_params)
    IO.puts("✓ Master tenant '#{master_params["external_id"]}' created")
  tenant ->
    {:ok, _} = Supavisor.Tenants.update_tenant(tenant, master_params)
    IO.puts("✓ Master tenant '#{master_params["external_id"]}' updated")
end

case Supavisor.Tenants.get_tenant_by_external_id(replica1_params["external_id"]) do
  nil ->
    {:ok, _} = Supavisor.Tenants.create_tenant(replica1_params)
    IO.puts("✓ Replica tenant '#{replica1_params["external_id"]}' created")
  tenant ->
    {:ok, _} = Supavisor.Tenants.update_tenant(tenant, replica1_params)
    IO.puts("✓ Replica tenant '#{replica1_params["external_id"]}' updated")
end

# Create cluster
cluster_params = %{
  "alias" => tenant_id,
  "active" => true,
  "cluster_tenants" => [
    %{
      "type" => "write",
      "cluster_alias" => tenant_id,
      "tenant_external_id" => "#{tenant_id}_master",
      "active" => true
    },
    %{
      "type" => "read",
      "cluster_alias" => tenant_id,
      "tenant_external_id" => "#{tenant_id}_replica1",
      "active" => true
    }
  ]
}

# Create or update cluster
if !Supavisor.Tenants.get_cluster_by_alias(tenant_id) do
  {:ok, _} = Supavisor.Tenants.create_cluster(cluster_params)
  IO.puts("✓ Cluster '#{tenant_id}' created with master and replicas")
else
  IO.puts("✓ Cluster '#{tenant_id}' already exists")
end
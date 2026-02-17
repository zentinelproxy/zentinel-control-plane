# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     ZentinelCp.Repo.insert!(%ZentinelCp.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Dev admin user
case ZentinelCp.Accounts.register_user(%{
       email: "admin@localhost",
       password: "changeme123456",
       role: "admin"
     }) do
  {:ok, user} ->
    IO.puts("Created admin user: #{user.email}")

  {:error, %{errors: [email: {"has already been taken", _}]}} ->
    IO.puts("Admin user already exists")

  {:error, changeset} ->
    IO.inspect(changeset.errors, label: "Failed to create admin user")
end

# Dev org with admin as owner
admin = ZentinelCp.Accounts.get_user_by_email("admin@localhost")

if admin do
  case ZentinelCp.Orgs.create_org_with_owner(%{name: "Default"}, admin) do
    {:ok, org} ->
      IO.puts("Created org: #{org.name} (slug: #{org.slug})")

    {:error, %{errors: [slug: {"has already been taken", _}]}} ->
      IO.puts("Default org already exists")

    {:error, reason} ->
      IO.inspect(reason, label: "Failed to create org")
  end
end

Postgrex.Types.define(
  EyeInTheSkyWeb.PostgrexTypes,
  [Pgvector.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(),
  []
)

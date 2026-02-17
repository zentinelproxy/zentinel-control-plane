defmodule ZentinelCpWeb.ApiDocsController do
  use ZentinelCpWeb, :controller

  @doc """
  Serves the API documentation using Scalar UI.
  """
  def index(conn, _params) do
    html = """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Zentinel Control Plane API Documentation</title>
        <meta name="description" content="REST API documentation for Zentinel Control Plane">
        <style>
          body {
            margin: 0;
            padding: 0;
          }
        </style>
      </head>
      <body>
        <script
          id="api-reference"
          data-url="/openapi.yaml"
          data-configuration='{
            "theme": "purple",
            "layout": "modern",
            "hiddenClients": ["unirest"],
            "defaultHttpClient": {
              "targetKey": "shell",
              "clientKey": "curl"
            },
            "metaData": {
              "title": "Zentinel Control Plane API",
              "description": "Fleet management API for Zentinel reverse proxies"
            }
          }'>
        </script>
        <script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference"></script>
      </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end
end

use lib 't';
use Test::APIcast::Blackbox 'no_plan';

# The output varies between requests, so run only once
repeat_each(1);

run_tests();

__DATA__

=== TEST 1: metrics endpoint works
--- configuration
{
}
--- request
GET /metrics
--- more_headers
Host: metrics
--- response_body
# HELP nginx_http_connections Number of HTTP connections
# TYPE nginx_http_connections gauge
nginx_http_connections{state="accepted"} 1
nginx_http_connections{state="active"} 1
nginx_http_connections{state="handled"} 1
nginx_http_connections{state="reading"} 0
nginx_http_connections{state="total"} 1
nginx_http_connections{state="waiting"} 0
nginx_http_connections{state="writing"} 1
# HELP nginx_metric_errors_total Number of nginx-lua-prometheus errors
# TYPE nginx_metric_errors_total counter
nginx_metric_errors_total 0
# HELP openresty_shdict_capacity OpenResty shared dictionary capacity
# TYPE openresty_shdict_capacity gauge
openresty_shdict_capacity{dict="api_keys"} 10485760
openresty_shdict_capacity{dict="batched_reports"} 1048576
openresty_shdict_capacity{dict="batched_reports_locks"} 1048576
openresty_shdict_capacity{dict="cached_auths"} 1048576
openresty_shdict_capacity{dict="configuration"} 10485760
openresty_shdict_capacity{dict="init"} 16384
openresty_shdict_capacity{dict="limiter"} 1048576
openresty_shdict_capacity{dict="locks"} 1048576
openresty_shdict_capacity{dict="prometheus_metrics"} 16777216
# HELP openresty_shdict_free_space OpenResty shared dictionary free space
# TYPE openresty_shdict_free_space gauge
openresty_shdict_free_space{dict="api_keys"} 10412032
openresty_shdict_free_space{dict="batched_reports"} 1032192
openresty_shdict_free_space{dict="batched_reports_locks"} 1032192
openresty_shdict_free_space{dict="cached_auths"} 1032192
openresty_shdict_free_space{dict="configuration"} 10412032
openresty_shdict_free_space{dict="init"} 4096
openresty_shdict_free_space{dict="limiter"} 1032192
openresty_shdict_free_space{dict="locks"} 1032192
openresty_shdict_free_space{dict="prometheus_metrics"} 16662528
--- error_code: 200
--- no_error_log
[error]

=== TEST 2: metric endpoints shows backend responses when the APIcast policy is in the chain
We do a couple of authorized requests to backend (2xx) and a couple of
unauthorized ones (4xx) and check that those metrics are shown correctly when
calling the prometheus metrics endpoint.
To simplify the output of the metrics endpoint, we use an environment config
that does not include the nginx metrics (tested in the previous test).
--- environment_file: t/fixtures/configs/without_nginx_metrics.lua
--- configuration
{
  "services": [
    {
      "id": 42,
      "backend_version":  1,
      "backend_authentication_type": "service_token",
      "backend_authentication_value": "token-value",
      "proxy": {
        "api_backend": "http://test:$TEST_NGINX_SERVER_PORT/",
        "proxy_rules": [
          { "pattern": "/", "http_method": "GET", "metric_system_name": "hits", "delta": 1 }
        ],
        "policy_chain": [
          { "name": "apicast.policy.apicast" }
        ]
      }
    }
  ]
}
--- upstream
  location / {
     content_by_lua_block {
       ngx.say('yay, api backend');
     }
  }
--- backend
  location /transactions/authrep.xml {
    content_by_lua_block {
      -- Check only the user key and assume the rest of params are OK
      if ngx.req.get_uri_args(0)['user_key'] == 'invalid' then
        ngx.exit(403)
      else
        ngx.exit(200)
      end
    }
  }
--- request eval
["GET /?user_key=valid", "GET /?user_key=valid", "GET /?user_key=invalid", "GET /?user_key=invalid", "GET /metrics"]
--- more_headers eval
["", "", "", "", "Host: metrics"]
--- error_code eval
[ 200, 200, 403, 403, 200 ]
--- response_body eval
[ "yay, api backend\x{0a}", "yay, api backend\x{0a}", "Authentication failed", "Authentication failed",
<<'METRICS_OUTPUT'
# HELP backend_response Response status codes from 3scale's backend
# TYPE backend_response counter
backend_response{status="2xx"} 2
backend_response{status="4xx"} 2
# HELP nginx_metric_errors_total Number of nginx-lua-prometheus errors
# TYPE nginx_metric_errors_total counter
nginx_metric_errors_total 0
METRICS_OUTPUT
]
--- no_error_log
[error]

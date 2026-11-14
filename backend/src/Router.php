<?php
declare(strict_types=1);

/** Router kecil: cocokkan metode + path, mendukung parameter seperti /siklus/{id}. */
class Router
{
    private array $routes = [];

    public function add(string $method, string $path, callable $handler): void
    {
        $regex = preg_replace('#\{(\w+)\}#', '(?P<$1>[^/]+)', $path);
        $this->routes[] = [strtoupper($method), '#^' . $regex . '$#', $handler];
    }

    public function dispatch(string $method, string $uri): void
    {
        $path = parse_url($uri, PHP_URL_PATH) ?: '/';

        // Buang awalan folder (misalnya /tanilog-repo/backend) agar rute tetap /auth/login
        $base = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '')), '/');
        if ($base !== '' && strpos($path, $base . '/') === 0) {
            $path = substr($path, strlen($base));
        }
        $path = '/' . trim($path, '/');

        $pathMatched = false;
        foreach ($this->routes as $route) {
            list($m, $regex, $handler) = $route;
            if (preg_match($regex, $path, $matches)) {
                $pathMatched = true;
                if ($m === strtoupper($method)) {
                    $params = array_filter($matches, 'is_string', ARRAY_FILTER_USE_KEY);
                    $handler($params);
                    return;
                }
            }
        }
        if ($pathMatched) {
            Response::error('Metode tidak diizinkan', 405);
        }
        Response::error('Endpoint tidak ditemukan', 404);
    }
}

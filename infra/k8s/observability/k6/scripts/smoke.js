import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = (__ENV.BASE_URL || 'http://localhost:3001').replace(/\/$/, '');

export const options = {
  vus: 1,
  iterations: 5,
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500'],
  },
};

function okOrNoContent(res) {
  return res.status === 200 || res.status === 204;
}

export default function smoke () {
  const health = http.get(`${BASE_URL}/health`, { tags: { name: 'GET /health' } });
  check(health, { 'health is 200': (r) => r.status === 200 });

  const ready = http.get(`${BASE_URL}/ready`, { tags: { name: 'GET /ready' } });
  check(ready, { 'ready is 200': (r) => r.status === 200 });

  const list = http.get(`${BASE_URL}/api/v1/articles/getPaginated?page=1&limit=20`, {
    tags: { name: 'GET /api/v1/articles/getPaginated' },
  });
  check(list, { 'articles is 200/204': okOrNoContent });

  sleep(0.2);
}


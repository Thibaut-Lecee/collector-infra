import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = (__ENV.BASE_URL || 'http://localhost:3001').replace(/\/$/, '');

export const options = {
  scenarios: {
    api_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '10s', target: 10 },
        { duration: '40s', target: 25 },
        { duration: '30s', target: 25 },
        { duration: '10s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<750', 'p(99)<1500'],
  },
};

function okOrNoContent(res) {
  return res.status === 200 || res.status === 204;
}

export default function () {
  const list = http.get(`${BASE_URL}/api/v1/articles/getPaginated?page=1&limit=20`, {
    tags: { name: 'GET /api/v1/articles/getPaginated' },
  });

  check(list, { 'articles is 200/204': okOrNoContent });

  // Optional DB ping; keep it lightweight.
  if (__ITER % 10 === 0) {
    const ready = http.get(`${BASE_URL}/ready`, { tags: { name: 'GET /ready' } });
    check(ready, { 'ready is 200': (r) => r.status === 200 });
  }

  sleep(0.1);
}


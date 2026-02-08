import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = (__ENV.BASE_URL || 'http://localhost:3001').replace(/\/$/, '');

export const options = {
  scenarios: {
    api_stress: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '10s', target: 10 },
        { duration: '20s', target: 25 },
        { duration: '20s', target: 50 },
        { duration: '20s', target: 75 },
        { duration: '10s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<1500', 'p(99)<2500'],
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
  sleep(0.05);
}


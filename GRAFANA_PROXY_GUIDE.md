# Grafana Reverse Proxy - Frontend Integration Guide

## Overview

Grafana is now accessible only to admin users through the Fastify API reverse proxy at `/internal/grafana/*`. This allows secure embedding of Grafana dashboards in the frontend.

---

## Authentication

### Admin Access Required

Only users with the `admin` role in Zitadel can access Grafana through the proxy.

**Request Headers:**
```http
GET /internal/grafana/... HTTP/1.1
Host: localhost:5005
Authorization: Bearer <admin-jwt-token>
```

**Non-Admin Response:**
```json
{
  "message": "Forbidden: Admin role required",
  "requiredRole": "admin"
}
```

---

## Iframe Embedding

### Basic Example

```html
<iframe 
  src="/internal/grafana/d/api-logs/api-logs-dashboard?orgId=1&kiosk=tv"
  width="100%"
  height="600px"
  frameborder="0"
  title="API Logs Dashboard"
></iframe>
```

### React Example

```tsx
import { useAuth } from '@/hooks/useAuth';

export function GrafanaDashboard() {
  const { user, token } = useAuth();
  
  // Only render for admin users
  if (!user?.roles?.includes('admin')) {
    return <div>Access Denied: Admin role required</div>;
  }

  const dashboardUrl = `/internal/grafana/d/api-logs/api-logs-dashboard?orgId=1&kiosk=tv&refresh=5s&from=now-1h&to=now`;

  return (
    <div className="grafana-container">
      <iframe
        src={dashboardUrl}
        width="100%"
        height="600px"
        frameBorder="0"
        title="API Logs Dashboard"
        allow="fullscreen"
      />
    </div>
  );
}
```

### Vue Example

```vue
<template>
  <div v-if="isAdmin" class="grafana-container">
    <iframe
      :src="dashboardUrl"
      width="100%"
      height="600px"
      frameborder="0"
      title="API Logs Dashboard"
    />
  </div>
  <div v-else>
    Access Denied: Admin role required
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { useAuth } from '@/composables/useAuth';

const { user } = useAuth();
const isAdmin = computed(() => user.value?.roles?.includes('admin'));

const dashboardUrl = computed(() => {
  const params = new URLSearchParams({
    orgId: '1',
    kiosk: 'tv',
    refresh: '5s',
    from: 'now-1h',
    to: 'now'
  });
  return `/internal/grafana/d/api-logs/api-logs-dashboard?${params}`;
});
</script>
```

---

## URL Parameters

### Kiosk Mode

Hide Grafana UI chrome for clean embedding:

| Parameter | Description |
|-----------|-------------|
| `kiosk` | Hides top navigation |
| `kiosk=tv` | Full kiosk mode (recommended for embedding) |

### Time Range

| Parameter | Description | Example |
|-----------|-------------|---------|
| `from` | Start time | `now-1h`, `now-24h`, `2024-01-01T00:00:00Z` |
| `to` | End time | `now`, `2024-01-02T00:00:00Z` |

### Auto-Refresh

| Parameter | Description | Example |
|-----------|-------------|---------|
| `refresh` | Auto-refresh interval | `5s`, `10s`, `1m`, `5m` |

### Organization

| Parameter | Description | Default |
|-----------|-------------|---------|
| `orgId` | Organization ID | `1` |

---

## Common Dashboard URLs

### API Logs Dashboard

```
/internal/grafana/d/api-logs/api-logs-dashboard?orgId=1&kiosk=tv&refresh=5s&from=now-1h&to=now
```

### Explore Logs (LogQL Query)

```
/internal/grafana/explore?orgId=1&kiosk&left={"datasource":"Loki","queries":[{"refId":"A","expr":"{service=\"api\"}"}],"range":{"from":"now-1h","to":"now"}}
```

### Custom Dashboard

```
/internal/grafana/d/<dashboard-uid>/<dashboard-slug>?orgId=1&kiosk=tv
```

---

## Creating Dashboards

### 1. Access Grafana Admin Panel

As an admin user, access the full Grafana UI:

```
http://localhost:5005/internal/grafana/
```

Login with:
- Username: `admin`
- Password: `admin`

### 2. Create Dashboard

1. Click **+ Create** → **Dashboard**
2. Add panels with LogQL queries
3. Save dashboard
4. Copy the dashboard UID from the URL

### 3. Get Embed URL

Dashboard URL format:
```
/d/<uid>/<slug>?orgId=1&kiosk=tv
```

Example:
```
/internal/grafana/d/abc123/my-dashboard?orgId=1&kiosk=tv
```

---

## LogQL Query Examples

### All API Logs

```logql
{service="api"}
```

### Errors Only

```logql
{service="api"} | json | level="error"
```

### Specific Endpoint

```logql
{service="api"} | json | url=~"/api/v1/articles.*"
```

### Slow Requests

```logql
{service="api"} | json | msg="Request completed" | responseTime > 1000
```

### By Request ID

```logql
{service="api"} | json | requestId="your-request-id"
```

---

## Security Considerations

### Frontend

- **Always check user role** before rendering iframe
- **Include Authorization header** in all requests to `/internal/grafana/*`
- **Handle 403 responses** gracefully

### Backend

- **Authentication required**: All requests must include valid JWT
- **Admin role required**: Only users with admin role can access
- **Headers stripped**: Authorization and Cookie headers removed before proxying
- **No direct access**: Grafana port not exposed publicly

---

## Troubleshooting

### Iframe Not Loading

**Check browser console for errors:**
```javascript
// CORS error
// Solution: Ensure CORS_ORIGIN includes your frontend URL

// 403 Forbidden
// Solution: Verify user has admin role

// 401 Unauthorized
// Solution: Include Authorization header with valid JWT
```

### Dashboard Not Found

**Verify dashboard UID:**
```bash
# List all dashboards
curl -H "Authorization: Bearer <admin-token>" \
  http://localhost:5005/internal/grafana/api/search
```

### Auto-Refresh Not Working

**Check refresh parameter:**
```
# Correct
?refresh=5s

# Incorrect
?refresh=5
```

---

## Example: Full Page with Multiple Dashboards

```tsx
import { useState } from 'react';

const dashboards = [
  {
    id: 'api-logs',
    title: 'API Logs',
    url: '/internal/grafana/d/api-logs/api-logs-dashboard?orgId=1&kiosk=tv&refresh=5s',
  },
  {
    id: 'errors',
    title: 'Error Tracking',
    url: '/internal/grafana/d/errors/error-dashboard?orgId=1&kiosk=tv&refresh=10s',
  },
];

export function MonitoringPage() {
  const [selectedDashboard, setSelectedDashboard] = useState(dashboards[0]);

  return (
    <div className="monitoring-page">
      <nav className="dashboard-tabs">
        {dashboards.map((dashboard) => (
          <button
            key={dashboard.id}
            onClick={() => setSelectedDashboard(dashboard)}
            className={selectedDashboard.id === dashboard.id ? 'active' : ''}
          >
            {dashboard.title}
          </button>
        ))}
      </nav>
      
      <div className="dashboard-container">
        <iframe
          key={selectedDashboard.id}
          src={selectedDashboard.url}
          width="100%"
          height="800px"
          frameBorder="0"
          title={selectedDashboard.title}
        />
      </div>
    </div>
  );
}
```

---

## Next Steps

1. **Create custom dashboards** in Grafana admin panel
2. **Copy dashboard UIDs** for embedding
3. **Implement frontend components** with iframe
4. **Test with admin and non-admin users**
5. **Configure auto-refresh** for real-time monitoring

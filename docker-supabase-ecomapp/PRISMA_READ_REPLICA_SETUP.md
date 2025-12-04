# Prisma Read Replica Configuration Guide

## Current Setup Status

✅ **PostgreSQL Primary Database**: `supabase-db` (port 5432)
✅ **PostgreSQL Read Replica**: `supabase-db-replica-1` (port 5432, exposed on host as 54325)
✅ **Replication Status**: Active with 0 bytes lag
✅ **Replica Mode**: Read-only (in recovery mode)

## Prisma Read Replica Configuration

### 1. Update Prisma Schema

Your current schema at `/data/code/backend-nestjs/prisma/schema.prisma` needs to be updated:

```prisma
datasource db {
  provider = "postgresql"  // Changed from mysql
  url      = env("DATABASE_URL")
  // Add read replicas configuration
  directUrl = env("DIRECT_URL")
}

generator client {
  provider = "prisma-client-js"
  previewFeatures = ["readReplicas"]  // Enable read replica feature
}

// ... rest of your models
```

### 2. Environment Variables

Add these to your `.env` file:

```bash
# Primary database (for writes and transactions)
DATABASE_URL="postgresql://postgres:ffJYi56gSxRedvUy0rU9PEpk@supabase-db:5432/postgres"

# Direct connection (same as DATABASE_URL in most cases)
DIRECT_URL="postgresql://postgres:ffJYi56gSxRedvUy0rU9PEpk@supabase-db:5432/postgres"

# Read replica URL
DATABASE_REPLICA_URL="postgresql://postgres:ffJYi56gSxRedvUy0rU9PEpk@supabase-db-replica-1:5432/postgres"
```

### 3. Update PrismaService

Update `/data/code/backend-nestjs/src/shared/services/prisma.service.ts`:

```typescript
import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  constructor() {
    super({
      log: ['query', 'info', 'warn', 'error'],
      // Configure read replicas
      datasources: {
        db: {
          url: process.env.DATABASE_URL,
        },
      },
    });

    // Enable read replicas
    if (process.env.DATABASE_REPLICA_URL) {
      this.$extends({
        name: 'readReplica',
        query: {
          $allOperations({ operation, model, args, query }) {
            // Route read operations to replica
            const readOperations = ['findUnique', 'findFirst', 'findMany', 'count', 'aggregate', 'groupBy'];

            if (readOperations.includes(operation)) {
              // Use replica for read operations
              return query({
                ...args,
                datasources: {
                  db: {
                    url: process.env.DATABASE_REPLICA_URL,
                  },
                },
              });
            }

            // Use primary for write operations
            return query(args);
          },
        },
      });
    }
  }

  async onModuleInit() {
    try {
      await this.$connect();
      console.log('✓ Connected to database');
      if (process.env.DATABASE_REPLICA_URL) {
        console.log('✓ Read replica configured');
      }
    } catch (e) {
      console.error('Database connection error:', e);
    }
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
```

### 4. Alternative: Using Prisma's Built-in Read Replica Support (Recommended)

**Note**: Prisma 5.7.1 (your current version) supports read replicas via extensions. Here's the recommended approach:

```typescript
import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { withAccelerate } from '@prisma/extension-accelerate'; // Optional

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  constructor() {
    const replicaUrl = process.env.DATABASE_REPLICA_URL;

    super({
      log: ['query', 'info', 'warn', 'error'],
      datasources: {
        db: {
          url: process.env.DATABASE_URL,
        },
      },
    });

    // Add read replica support using Prisma Client Extensions
    if (replicaUrl) {
      const primaryClient = this;
      const replicaClient = new PrismaClient({
        datasources: {
          db: {
            url: replicaUrl,
          },
        },
      });

      // Store replica client for read operations
      (this as any).$replica = replicaClient;
    }
  }

  async onModuleInit() {
    try {
      await this.$connect();
      if ((this as any).$replica) {
        await (this as any).$replica.$connect();
        console.log('✓ Connected to primary and replica databases');
      }
    } catch (e) {
      console.log(e);
    }
  }

  async onModuleDestroy() {
    await this.$disconnect();
    if ((this as any).$replica) {
      await (this as any).$replica.$disconnect();
    }
  }

  // Helper method to use replica for reads
  get replica() {
    return (this as any).$replica || this;
  }
}
```

### 5. Usage in Services

Update your services to use the replica for read operations:

```typescript
// In your service files (e.g., article.service.ts)

// For READ operations - use replica
const articles = await this.prisma.replica.article.findMany({
  where: { published: true },
});

// For WRITE operations - use primary
const newArticle = await this.prisma.article.create({
  data: articleData,
});
```

## Testing Read Replica Routing

### Test Script 1: Basic Replica Test
```bash
./test-replica-routing.sh
```

### Test Script 2: Real-time Query Monitoring
```bash
./monitor-db-queries.sh
```

Then make some API calls to your application and watch:
- Read operations (GET requests) should appear on the **Replica**
- Write operations (POST, PUT, DELETE) should appear on the **Primary**

### Test Script 3: Manual Query Test

Run a test query directly on each database:

```bash
# Test Primary
docker exec supabase-db psql -U postgres -d postgres -c "SELECT 'PRIMARY' as db, now() as time;"

# Test Replica
docker exec supabase-db-replica-1 psql -U postgres -d postgres -c "SELECT 'REPLICA' as db, now() as time;"
```

### Test Script 4: Check Query Logs

Enable detailed logging in Prisma to see which database receives queries:

```typescript
// In prisma.service.ts constructor
super({
  log: [
    { emit: 'event', level: 'query' },
    { emit: 'stdout', level: 'info' },
    { emit: 'stdout', level: 'warn' },
    { emit: 'stdout', level: 'error' },
  ],
});

// Add event listener
this.$on('query', (e) => {
  console.log('Query: ' + e.query);
  console.log('Duration: ' + e.duration + 'ms');
});
```

## Verification Steps

1. ✅ **Replication is working**: Confirmed with 0 bytes lag
2. ✅ **Replica is read-only**: Confirmed in recovery mode
3. ✅ **Both databases are accessible**: Connection tests passed
4. ⚠️ **Prisma configuration**: Needs to be updated (see above)
5. ⏳ **Query routing**: Can be verified after Prisma update

## Next Steps

1. Update your Prisma schema to use PostgreSQL (currently set to MySQL)
2. Regenerate Prisma Client: `npx prisma generate`
3. Update PrismaService with read replica configuration
4. Test with your application
5. Monitor query distribution using the monitoring script

## Database Connection Details

| Database | Container | Internal Port | External Port | Purpose |
|----------|-----------|---------------|---------------|---------|
| Primary | supabase-db | 5432 | - | Write + Read |
| Replica 1 | supabase-db-replica-1 | 5432 | 54325 | Read Only |

## Connection Strings

```bash
# From within Docker network
Primary:  postgresql://postgres:ffJYi56gSxRedvUy0rU9PEpk@supabase-db:5432/postgres
Replica:  postgresql://postgres:ffJYi56gSxRedvUy0rU9PEpk@supabase-db-replica-1:5432/postgres

# From host machine
Primary:  postgresql://postgres:ffJYi56gSxRedvUy0rU9PEpk@localhost:5432/postgres
Replica:  postgresql://postgres:ffJYi56gSxRedvUy0rU9PEpk@localhost:54325/postgres
```

## Performance Benefits

- **Reduced load on primary**: Read queries distributed to replica
- **Better write performance**: Primary focuses on writes
- **Scalability**: Can add more read replicas as needed
- **High availability**: Replica can be promoted if primary fails

## Important Notes

- ⚠️ **Replication Lag**: Currently 0 bytes, but monitor in production
- ⚠️ **Read-after-write**: Be careful with immediate reads after writes
- ⚠️ **Transactions**: Always use primary database for transactions
- ⚠️ **Schema migrations**: Run only on primary (will replicate automatically)

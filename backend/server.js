
const express = require('express')
const cors = require('cors')
const { Pool } = require('pg')
const redis = require('redis')

const app = express()

app.use(cors())

// Use environment variables for configuration
const redisClient = redis.createClient({
  url: process.env.REDIS_URL || 'redis://redis:6379'
})

redisClient.on('error', (err) => console.log('Redis Client Error', err));

redisClient.connect()
const pgPool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false } // Adjust based on OCI DB SSL configuration
});

// A separate script should handle database migrations (like CREATE TABLE).
// Running CREATE TABLE on every request is inefficient.

// Lightweight health check for Docker
app.get('/health', (req, res) => {
  // This endpoint should be as simple as possible.
  // It confirms the Node.js process is running and responsive.
  res.status(200).send('OK');
});

app.get('/api/status', async(req,res)=>{

  try{
    // A health check should be lightweight and not have side-effects like writing to the DB.
    // Let's check connectivity and report status.

    // Check Redis
    await redisClient.set('health', 'ok', { EX: 10 }) // Set with a 10-second expiry
    const redisValue = await redisClient.get('health')

    // Check PostgreSQL
    const pgClient = await pgPool.connect()
    const { rows } = await pgClient.query('SELECT 1 AS solution')
    pgClient.release()

    res.json({
      message: 'API is running',
      redis: redisValue === 'ok' ? 'ok' : 'error',
      postgres: rows && rows[0].solution === 1 ? 'ok' : 'error',
      server:process.env.HOSTNAME
    })

  }catch(err){
    console.error('Health check failed:', err); // Log the full error on the server
    res.status(500).json({
      error: 'An internal server error occurred.' // Avoid leaking implementation details to the client
    })
  }
})

const port = process.env.PORT || 3003;
app.listen(port,()=>{
  console.log(`API running on port ${port}`)
})

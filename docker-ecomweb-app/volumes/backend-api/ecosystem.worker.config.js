module.exports = {
    apps: [
        {
            name: 'temporal_worker',
            script: '/app/dist/main.js',
            instances: 1, // Multiple workers for better throughput
            exec_mode: "cluster",
            max_memory_restart: '1000M',
            watch: false,
            env: {
                NODE_ENV: 'production',
                IS_CRON_WORKER: 'false',
                IS_TEMPORAL_WORKER: 'true',
            },
        },
    ],
};

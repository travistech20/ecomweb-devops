module.exports = {
    apps: [
        {
            name: 'api_service',
            script: '/app/dist/main.js',
            instances: 1,
            exec_mode: "cluster",
            max_memory_restart: '1000M',
            watch: false,
            env: {
                NODE_ENV: 'production',
                IS_CRON_WORKER: 'false',
            },
        },
        {
            name: 'cron',
            script: '/app/dist/main.js',
            instances: 1,
            exec_mode: "fork",
            max_memory_restart: '1000M',
            watch: false,
            env: {
                NODE_ENV: 'production',
                IS_CRON_WORKER: 'true',
            },
        },
        {
            name: 'temporal',
            script: '/app/dist/main.js',
            instances: 1,
            exec_mode: "fork",
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

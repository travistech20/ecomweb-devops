module.exports = {
    apps: [
        {
            name: 'cron_worker',
            script: '/app/dist/main.js',
            instances: 1,
            exec_mode: "fork",
            max_memory_restart: '1000M',
            watch: false,
            env: {
                NODE_ENV: 'production',
                IS_CRON_WORKER: 'true',
                IS_TEMPORAL_WORKER: 'false',
            },
        },
    ],
};

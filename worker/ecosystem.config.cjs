module.exports = {
  apps: [
    {
      name: 'ivmet-worker',
      script: 'dist/index.js',
      args: 'daemon',
      cwd: __dirname,
      instances: 1,
      autorestart: true,
      watch: false,
      restart_delay: 5000,
      max_memory_restart: '300M',
      time: true,
      env: {
        NODE_ENV: 'production',
      },
    },
  ],
};

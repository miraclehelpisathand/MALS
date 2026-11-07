// Task 5 remains opt-in until its migrations, scheduler and security testing
// are complete. Never enable this against the current development database.
export const certificatesEnabled = import.meta.env.VITE_CERTIFICATES_ENABLED === 'true';

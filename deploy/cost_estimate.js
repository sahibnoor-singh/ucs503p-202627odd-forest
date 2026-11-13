#!/usr/bin/env node
// How long do the AWS credits last? Edit the numbers at the top (or pass them: node deploy/cost_estimate.js --credits 167 --users 15),
// run it, and read the table. It only does arithmetic on the assumptions below; check each price against the provider's own pricing
// page before you rely on it (they were read from third-party price lists in November 2026, region Mumbai ap-south-1).
//
//   node deploy/cost_estimate.js                    # the default scenarios
//   node deploy/cost_estimate.js --credits 167 --users 40 --videosPerDay 30 --mbPerVideo 8

const args = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  if (argv[i].startsWith('--')) args[argv[i].slice(2)] = Number(argv[i + 1]);
}

const P = {
  credits: args.credits ?? 167, // dollars left
  hoursPerMonth: 730,
  // compute, dollars per hour (EC2 on-demand, Linux) or per month (Lightsail plan)
  ec2_t3_small: 0.0224, // 2 vCPU burstable, 2 GB
  ec2_t3_medium: 0.0448, // 2 vCPU burstable, 4 GB
  lightsail_2gb_month: 12, // 2 vCPU, 2 GB, 60 GB SSD, static IP included (transfer allowance: verify, about 3 TB)
  ebs_gb: 30,
  ebs_per_gb: 0.08, // EC2 disk (gp3)
  ipv4_month: 3.65, // a public IPv4 address on EC2: $0.005 an hour
  s3_backup_gb: 10,
  s3_per_gb: 0.025, // off-site backups
  egress_free_gb: 100,
  egress_per_gb: 0.11, // EC2 data transfer out to the internet, Mumbai (US is 0.09)
  // Gemini is billed by Google, not from AWS credits. Rough audio-in + text-out price per analysed video (2.5-Flash class prices).
  gemini_per_video: 0.005
};

const scenarios = [
  { name: 'Closed alpha, 15 people', users: args.users ?? 15, videosPerDay: args.videosPerDay ?? 25, mbPerVideo: args.mbPerVideo ?? 10, postsPerUserPerDay: 0.5 },
  { name: 'Campus pilot, 100 people', users: 100, videosPerDay: 25, mbPerVideo: 10, postsPerUserPerDay: 0.5 },
  { name: 'Campus pilot, 100 people, videos shrunk to ~3 MB', users: 100, videosPerDay: 25, mbPerVideo: 3, postsPerUserPerDay: 0.5 }
];

const hosts = [
  { name: 'Oracle Always Free (ARM)', fixed: 0, egressFree: 10000, egressRate: 0, ipv4: 0, disk: 0, oracle: true },
  { name: 'AWS Lightsail 2 GB', fixed: P.lightsail_2gb_month, egressFree: 3000, egressRate: 0.09, ipv4: 0, disk: 0 },
  { name: 'AWS EC2 t3.small', fixed: P.ec2_t3_small * P.hoursPerMonth, egressFree: P.egress_free_gb, egressRate: P.egress_per_gb, ipv4: P.ipv4_month, disk: P.ebs_gb * P.ebs_per_gb },
  { name: 'AWS EC2 t3.medium', fixed: P.ec2_t3_medium * P.hoursPerMonth, egressFree: P.egress_free_gb, egressRate: P.egress_per_gb, ipv4: P.ipv4_month, disk: P.ebs_gb * P.ebs_per_gb }
];

const money = (n) => `$${n.toFixed(n < 10 ? 2 : 0)}`;
const rows = [];
for (const s of scenarios) {
  const egressGb = (s.users * s.videosPerDay * s.mbPerVideo * 30) / 1000;
  const uploadsGbPerMonth = (s.users * s.postsPerUserPerDay * 12 * 30) / 1000; // about 12 MB per uploaded video
  const geminiPerMonth = s.users * s.postsPerUserPerDay * 30 * P.gemini_per_video;
  for (const h of hosts) {
    const egress = Math.max(0, egressGb - h.egressFree) * h.egressRate;
    const backups = P.s3_backup_gb * P.s3_per_gb; // Oracle's own AWS bill is only the S3 backup copy
    const awsMonthly = h.oracle ? backups : h.fixed + h.ipv4 + h.disk + egress + backups;
    const months = awsMonthly > 0 ? P.credits / awsMonthly : Infinity;
    rows.push({
      scenario: s.name,
      host: h.name,
      'watched GB/mo': Math.round(egressGb),
      'new uploads GB/mo': Math.round(uploadsGbPerMonth),
      'AWS bill $/mo': money(awsMonthly),
      'credits last (months)': Number.isFinite(months) ? months.toFixed(1) : 'n/a',
      'Gemini $/mo (not credits)': money(geminiPerMonth)
    });
  }
}
console.log(`Credits: ${money(P.credits)}   (AWS credits expire after 6 or 12 months, whichever your Billing console shows, so the months below are an upper limit)\n`);
console.table(rows);

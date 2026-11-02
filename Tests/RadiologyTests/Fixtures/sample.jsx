import React from "react";

const Badge = ({ label }) => <span className="badge">{label}</span>;

export function ScanList({ scans }) {
  return (
    <ul className="scans" data-count={scans.length}>
      {scans.map((scan) => (
        <li key={scan.id}>
          <Badge label={scan.title} />
          胸部
        </li>
      ))}
    </ul>
  );
}

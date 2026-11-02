import React, { type FC } from "react";

interface Props {
  scans: ReadonlyArray<{ id: string; title: string }>;
}

const Badge: FC<{ label: string }> = ({ label }) => <span className="badge">{label}</span>;

export const ScanList: FC<Props> = ({ scans }) => {
  const total: number = scans.length;
  return (
    <ul className="scans" data-count={total}>
      {scans.map((scan) => (
        <li key={scan.id}>
          <Badge label={scan.title} />
          胸部
        </li>
      ))}
    </ul>
  );
};

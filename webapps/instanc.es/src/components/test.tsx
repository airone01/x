'use client';

import { useEffect, useState } from "react";

const BackgroundFetcher = () => {
  "use client"

  const [data, setData] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchData = async () => {
      try {
        const response = await fetch('http://mirrors.ucr.ac.cr/debian-cd/');
        if (!response.ok) throw new Error('Network response failed');
        const result = await response.text();
        setData(result);
      } catch (err) {
        if (err instanceof Error)
          setError(err.message);
      }
    };

    // eslint-disable-next-line @typescript-eslint/no-floating-promises
    fetchData();

    // Optional: Set up periodic refetching
    // eslint-disable-next-line @typescript-eslint/no-misused-promises
    const interval = setInterval(fetchData, 5000); // Refetch every 5 seconds

    return () => clearInterval(interval);
  }, []);

  if (error) return <div className="text-red-500">Error: {error}</div>;
  if (!data) return <div className="text-gray-500">Loading...</div>;

  return (
    <div className="p-4">
      <pre className="whitespace-pre-wrap">{data}</pre>
    </div>
  );
};

export { BackgroundFetcher };

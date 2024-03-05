import { NextApiRequest, NextApiResponse } from "next";

export function GET(req: NextApiRequest, res: NextApiResponse) {
  const { user } = req?.query || { user: "World" };
  const message = `Hello, ${user}!`;

  return Response.json({ message });
}

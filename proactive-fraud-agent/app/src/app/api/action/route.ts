import { NextRequest, NextResponse } from 'next/server';
import { updateStatus } from '@/lib/snowflake';

export async function POST(req: NextRequest) {
  const formData = await req.formData();
  const customerId = formData.get('customerId') as string;
  const action = formData.get('action') as string;

  const statusMap: Record<string, string> = {
    ESCALATE: 'ESCALATED',
    MONITOR: 'MONITORING',
    CLEAR: 'CLEARED',
  };

  try {
    await updateStatus(customerId, statusMap[action] || action);
    return NextResponse.redirect(new URL(`/investigate/${customerId}`, req.url), 303);
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

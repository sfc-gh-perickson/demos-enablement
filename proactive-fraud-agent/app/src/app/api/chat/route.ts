import { NextRequest, NextResponse } from 'next/server';
import { continueThread, startNewThread } from '@/lib/snowflake';

export async function POST(req: NextRequest) {
  const { threadId, parentMessageId, customerId, message } = await req.json();

  const contextualPrompt = `[Investigating customer ${customerId}]\n\nUser question: ${message}`;

  try {
    let response;
    if (threadId && parentMessageId) {
      response = await continueThread(threadId, parentMessageId, contextualPrompt);
    } else {
      response = await startNewThread(contextualPrompt);
    }
    return NextResponse.json(response);
  } catch (e: any) {
    return NextResponse.json({ text: `Error: ${e.message}`, parentMessageId: parentMessageId || '' }, { status: 500 });
  }
}

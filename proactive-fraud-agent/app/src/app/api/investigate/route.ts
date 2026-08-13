import { NextRequest, NextResponse } from 'next/server';
import { executeQuery } from '@/lib/snowflake';

export async function POST(req: NextRequest) {
  const { customerId } = await req.json();

  if (!customerId) {
    return NextResponse.json({ error: 'Missing customerId' }, { status: 400 });
  }

  try {
    const priority = await executeQuery(`
      SELECT CUSTOMER_ID, PRIORITY_RANK, FRAUD_PROBABILITY, TOP_FACTORS
      FROM FRAUD_DETECTION_DEMO.APP.PRIORITIES
      WHERE CUSTOMER_ID = ?
      LIMIT 1
    `, [customerId]);

    if (!priority.length) {
      return NextResponse.json({ error: 'Customer not found in priorities' }, { status: 404 });
    }

    const p = priority[0];
    const prompt = `Investigate customer ${p.CUSTOMER_ID} for potential fraud.

Fraud Probability: ${p.FRAUD_PROBABILITY}
Priority Rank: ${p.PRIORITY_RANK}
Top Risk Factors (SHAP analysis):
${typeof p.TOP_FACTORS === 'string' ? p.TOP_FACTORS : JSON.stringify(p.TOP_FACTORS)}

Please analyze:
1. What fraud pattern do these risk factors suggest?
2. What is the severity level (CRITICAL/HIGH/MEDIUM/LOW)?
3. What specific transaction behaviors are concerning?
4. What is your recommended action (ESCALATE/MONITOR/BLOCK/CLEAR)?

Provide a concise investigation report.`;

    const requestBody = JSON.stringify({
      messages: [{ role: 'user', content: [{ type: 'text', text: prompt }] }],
    });

    const agentResult = await executeQuery(`
      SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
        'FRAUD_DETECTION_DEMO.APP.FRAUD_INVESTIGATOR',
        ?,
        TRUE
      ) AS response
    `, [requestBody]);

    const raw = agentResult[0]?.RESPONSE || agentResult[0]?.response;
    if (!raw) {
      return NextResponse.json({ error: 'No response from agent' }, { status: 500 });
    }

    const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
    const content = parsed.content || [];
    const textParts = content.filter((c: any) => c.type === 'text').map((c: any) => c.text);
    const responseText = textParts.join('\n') || JSON.stringify(parsed);

    const metadata = parsed.metadata || {};
    const threadId = String(metadata.thread_id || '');
    const parentMsgId = String(metadata.message_id || metadata.run_id || '');

    // Determine recommended action
    let action = 'MONITOR';
    const upper = responseText.toUpperCase();
    if (upper.includes('ESCALATE')) action = 'ESCALATE';
    else if (upper.includes('BLOCK')) action = 'BLOCK';
    else if (upper.includes('CLEAR')) action = 'CLEAR';

    const topFactorsJson = typeof p.TOP_FACTORS === 'string'
      ? p.TOP_FACTORS
      : JSON.stringify(p.TOP_FACTORS);

    // Insert report
    await executeQuery(`
      INSERT INTO FRAUD_DETECTION_DEMO.APP.INVESTIGATION_REPORTS
      (CUSTOMER_ID, PRIORITY_RANK, FRAUD_PROBABILITY, TOP_FACTORS,
       INVESTIGATION_REPORT, RECOMMENDED_ACTION, THREAD_ID, PARENT_MESSAGE_ID)
      SELECT ?, ?, ?, PARSE_JSON(?), ?, ?, ?, ?
    `, [
      customerId, p.PRIORITY_RANK, p.FRAUD_PROBABILITY, topFactorsJson,
      responseText.slice(0, 15000), action, threadId, parentMsgId,
    ]);

    // Update status
    await executeQuery(`
      UPDATE FRAUD_DETECTION_DEMO.APP.PRIORITIES
      SET INVESTIGATION_STATUS = 'AGENT_REVIEWED'
      WHERE CUSTOMER_ID = ?
    `, [customerId]);

    return NextResponse.json({ success: true, action, threadId, parentMessageId: parentMsgId });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

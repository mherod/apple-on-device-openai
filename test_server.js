#!/usr/bin/env node
/**
 * Test Apple On-Device OpenAI Compatible Server
 * Make sure the server is running at http://localhost:11535 before running this script
 *
 * Usage: node test_server.js
 * Requires: npm install openai
 */

import OpenAI from "openai";

const log = (...args) => process.stdout.write(args.join(" ") + "\n");

const BASE_URL = "http://127.0.0.1:11535";
const API_BASE_URL = `${BASE_URL}/v1`;

const client = new OpenAI({ baseURL: API_BASE_URL, apiKey: "dummy-key" });

async function testHealthCheck() {
  process.stdout.write("🔍 Testing health check... ");
  const res = await fetch(`${BASE_URL}/health`);
  if (res.ok) {
    log("✅ passed");
    return true;
  }
  log(`❌ failed: ${res.status}`);
  return false;
}

async function testStatus() {
  log("\n🔍 Testing server status...");
  const res = await fetch(`${BASE_URL}/status`);
  if (!res.ok) {
    log(`❌ failed: ${res.status}`);
    return false;
  }
  const data = await res.json();
  log("✅ Status check passed");
  log(`   Model available: ${data.model_available ?? false}`);
  log(`   Reason: ${data.reason ?? "N/A"}`);
  log(`   Supported languages count: ${(data.supported_languages ?? []).length}`);
  return data.model_available ?? false;
}

async function testModelsList() {
  log("\n🔍 Testing models list (OpenAI SDK)...");
  const models = await client.models.list();
  log("✅ Models list retrieved successfully");
  log(`   Available models count: ${models.data.length}`);
  for (const model of models.data) log(`   - ${model.id}`);
  return true;
}

async function testChatCompletion() {
  log("\n🔍 Testing multi-turn chat completion (OpenAI SDK)...");
  const response = await client.chat.completions.create({
    model: "apple-on-device",
    messages: [
      { role: "user", content: "What are the benefits of on-device AI?" },
      {
        role: "assistant",
        content:
          "On-device AI offers several key benefits including improved privacy, faster response times, reduced reliance on internet connectivity, and better data security since processing happens locally on your device.",
      },
      { role: "user", content: "Can you elaborate on the privacy benefits?" },
    ],
    max_tokens: 200,
  });
  log("✅ Multi-turn OpenAI SDK call successful");
  log(`   Response ID: ${response.id}`);
  log(`   Model: ${response.model}`);
  log(`   AI Response: ${response.choices[0].message.content}`);
  return true;
}

async function testChineseConversation() {
  log("\n🔍 Testing Chinese conversation (OpenAI SDK)...");
  const response = await client.chat.completions.create({
    model: "apple-on-device",
    messages: [{ role: "user", content: "你好！请用中文解释一下什么是苹果智能。" }],
    max_tokens: 200,
  });
  log("✅ Chinese conversation successful");
  log(`   AI Response: ${response.choices[0].message.content}`);
  return true;
}

async function testStreamingChatCompletion() {
  log("\n🔍 Testing streaming chat completion (OpenAI SDK)...");
  const stream = await client.chat.completions.create({
    model: "apple-on-device",
    messages: [{ role: "user", content: "Tell me a short story about AI helping humans." }],
    max_tokens: 150,
    stream: true,
  });
  log("✅ Streaming chat completion started");
  let collectedContent = "";
  let chunkCount = 0;
  for await (const chunk of stream) {
    const content = chunk.choices[0]?.delta?.content;
    if (content != null) {
      collectedContent += content;
      chunkCount++;
      process.stdout.write(`   Chunk ${chunkCount}: '${content}'\n`);
    }
  }
  log(`✅ Streaming completed with ${chunkCount} chunks`);
  log(`   Full response: ${collectedContent}`);
  return true;
}

async function main() {
  log("🚀 Starting Apple On-Device OpenAI Compatible Server Tests");
  log("=".repeat(60));

  if (!(await testHealthCheck())) {
    log("\n❌ Server unreachable, please ensure the server is running");
    process.exit(1);
  }

  const modelAvailable = await testStatus();
  await testModelsList();

  if (modelAvailable) {
    log("\n" + "=".repeat(60));
    log("🤖 Model available, starting chat tests");
    log("=".repeat(60));

    await testChatCompletion();
    await testChineseConversation();

    log("\n" + "=".repeat(60));
    log("🌊 Testing streaming functionality");
    log("=".repeat(60));

    await testStreamingChatCompletion();

    log("\n" + "=".repeat(60));
    log("✅ All tests completed!");
    log(`\n💡 Base URL: ${API_BASE_URL}`);
    log("   API Key: any value (no real API key needed)");
    log("   Model: apple-on-device");
  } else {
    log("\n⚠️  Model unavailable, skipping chat tests");
    log("Please ensure:");
    log("1. Device supports Apple Intelligence");
    log("2. Apple Intelligence is enabled in Settings");
    log("3. Model download is complete");
  }
}

main().catch((err) => {
  process.stderr.write(`❌ Fatal error: ${err}\n`);
  process.exit(1);
});

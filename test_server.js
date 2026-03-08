#!/usr/bin/env node
/**
 * Test Apple On-Device OpenAI Compatible Server
 * Make sure the server is running at http://localhost:11535 before running this script
 *
 * Usage: node test_server.js
 * Requires: npm install openai
 */

import OpenAI from "openai";

const BASE_URL = "http://127.0.0.1:11535";
const API_BASE_URL = `${BASE_URL}/v1`;

const client = new OpenAI({ baseURL: API_BASE_URL, apiKey: "dummy-key" });

async function testHealthCheck() {
  process.stdout.write("🔍 Testing health check... ");
  const res = await fetch(`${BASE_URL}/health`);
  if (res.ok) {
    console.log("✅ passed");
    return true;
  }
  console.log(`❌ failed: ${res.status}`);
  return false;
}

async function testStatus() {
  console.log("\n🔍 Testing server status...");
  const res = await fetch(`${BASE_URL}/status`);
  if (!res.ok) {
    console.log(`❌ failed: ${res.status}`);
    return false;
  }
  const data = await res.json();
  console.log("✅ Status check passed");
  console.log(`   Model available: ${data.model_available ?? false}`);
  console.log(`   Reason: ${data.reason ?? "N/A"}`);
  console.log(`   Supported languages count: ${(data.supported_languages ?? []).length}`);
  return data.model_available ?? false;
}

async function testModelsList() {
  console.log("\n🔍 Testing models list (OpenAI SDK)...");
  const models = await client.models.list();
  console.log("✅ Models list retrieved successfully");
  console.log(`   Available models count: ${models.data.length}`);
  for (const model of models.data) console.log(`   - ${model.id}`);
  return true;
}

async function testChatCompletion() {
  console.log("\n🔍 Testing multi-turn chat completion (OpenAI SDK)...");
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
  console.log("✅ Multi-turn OpenAI SDK call successful");
  console.log(`   Response ID: ${response.id}`);
  console.log(`   Model: ${response.model}`);
  console.log(`   AI Response: ${response.choices[0].message.content}`);
  return true;
}

async function testChineseConversation() {
  console.log("\n🔍 Testing Chinese conversation (OpenAI SDK)...");
  const response = await client.chat.completions.create({
    model: "apple-on-device",
    messages: [{ role: "user", content: "你好！请用中文解释一下什么是苹果智能。" }],
    max_tokens: 200,
  });
  console.log("✅ Chinese conversation successful");
  console.log(`   AI Response: ${response.choices[0].message.content}`);
  return true;
}

async function testStreamingChatCompletion() {
  console.log("\n🔍 Testing streaming chat completion (OpenAI SDK)...");
  const stream = await client.chat.completions.create({
    model: "apple-on-device",
    messages: [{ role: "user", content: "Tell me a short story about AI helping humans." }],
    max_tokens: 150,
    stream: true,
  });
  console.log("✅ Streaming chat completion started");
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
  console.log(`✅ Streaming completed with ${chunkCount} chunks`);
  console.log(`   Full response: ${collectedContent}`);
  return true;
}

async function main() {
  console.log("🚀 Starting Apple On-Device OpenAI Compatible Server Tests");
  console.log("=".repeat(60));

  if (!(await testHealthCheck())) {
    console.log("\n❌ Server unreachable, please ensure the server is running");
    process.exit(1);
  }

  const modelAvailable = await testStatus();
  await testModelsList();

  if (modelAvailable) {
    console.log("\n" + "=".repeat(60));
    console.log("🤖 Model available, starting chat tests");
    console.log("=".repeat(60));

    await testChatCompletion();
    await testChineseConversation();

    console.log("\n" + "=".repeat(60));
    console.log("🌊 Testing streaming functionality");
    console.log("=".repeat(60));

    await testStreamingChatCompletion();

    console.log("\n" + "=".repeat(60));
    console.log("✅ All tests completed!");
    console.log(`\n💡 Base URL: ${API_BASE_URL}`);
    console.log("   API Key: any value (no real API key needed)");
    console.log("   Model: apple-on-device");
  } else {
    console.log("\n⚠️  Model unavailable, skipping chat tests");
    console.log("Please ensure:");
    console.log("1. Device supports Apple Intelligence");
    console.log("2. Apple Intelligence is enabled in Settings");
    console.log("3. Model download is complete");
  }
}

main().catch((err) => {
  console.error("❌ Fatal error:", err);
  process.exit(1);
});

"""
Converts sentence-transformers/multi-qa-MiniLM-L6-cos-v1 to CoreML.

The exported model bakes in mean pooling + L2 normalization, so the app
gets a ready-to-use 384-dim normalized embedding vector as output.

Usage:
    pip install torch transformers coremltools
    python convert_model.py
"""

import torch
import torch.nn as nn
from transformers import AutoModel
import coremltools as ct
import numpy as np

MODEL_NAME = "sentence-transformers/multi-qa-MiniLM-L6-cos-v1"
OUTPUT_PATH = "DocumentBrain/AI/MiniLM.mlpackage"


class EmbeddingModel(nn.Module):
    """Wraps a HuggingFace transformer with mean pooling + L2 normalization."""

    def __init__(self, base_model):
        super().__init__()
        self.base = base_model

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        hidden = self.base(input_ids=input_ids, attention_mask=attention_mask).last_hidden_state
        # Mean pooling: average non-padding token embeddings
        mask = attention_mask.unsqueeze(-1).float()
        pooled = (hidden * mask).sum(dim=1) / mask.sum(dim=1).clamp(min=1e-9)
        # L2 normalize so cosine similarity = dot product
        return nn.functional.normalize(pooled, p=2, dim=1)


def main():
    print(f"Loading {MODEL_NAME}...")
    base_model = AutoModel.from_pretrained(MODEL_NAME)
    base_model.eval()

    model = EmbeddingModel(base_model)
    model.eval()

    # Trace and export with fixed length 512 (matches BERTTokenizer.maxSequenceLength)
    seq_len = 512
    dummy_ids = torch.zeros(1, seq_len, dtype=torch.int32)
    dummy_mask = torch.ones(1, seq_len, dtype=torch.int32)

    print("Tracing model...")
    with torch.no_grad():
        traced = torch.jit.trace(model, (dummy_ids, dummy_mask))

    # Verify output shape
    with torch.no_grad():
        sample_out = traced(dummy_ids, dummy_mask)
    print(f"Output shape: {sample_out.shape}  (expect [1, 384])")
    assert sample_out.shape == (1, 384), f"Unexpected shape: {sample_out.shape}"

    # Fixed shape [1, 512] matches what BERTTokenizer always produces
    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, 512), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, 512), dtype=np.int32),
        ],
        outputs=[
            ct.TensorType(name="embedding", dtype=np.float32),
        ],
        minimum_deployment_target=ct.target.iOS16,
    )

    mlmodel.short_description = "multi-qa-MiniLM-L6-cos-v1 — Q&A retrieval embeddings (384-dim, L2-normalized)"
    mlmodel.save(OUTPUT_PATH)
    print(f"\nSaved to {OUTPUT_PATH}")
    print("Output description:", mlmodel.output_description)
    print("\nDone. Re-open the Xcode project to pick up the new model.")


if __name__ == "__main__":
    main()

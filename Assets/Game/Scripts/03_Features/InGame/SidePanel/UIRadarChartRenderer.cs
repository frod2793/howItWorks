using UnityEngine;
using UnityEngine.UI;

namespace Features.InGame
{
    public class UIRadarChartRenderer : MaskableGraphic
    {
        private float[] m_emotionValues = new float[5] { 0f, 0f, 0f, 0f, 0f };
        private const float m_maxRadius = 160f;
        private const float m_maxValue = 10f;

        public void SetEmotionValues(float sadness, float joy, float curiosity, float fear, float confusion)
        {
            m_emotionValues[0] = sadness;
            m_emotionValues[1] = joy;
            m_emotionValues[2] = curiosity;
            m_emotionValues[3] = fear;
            m_emotionValues[4] = confusion;
            SetAllDirty();
        }

        protected override void OnPopulateMesh(VertexHelper vh)
        {
            vh.Clear();

            Color32 gridColor = new Color32(60, 55, 52, 255);
            float lineWidth = 1.5f;

            for (int step = 1; step <= 5; step++)
            {
                float radius = m_maxRadius * (step / 5f);
                DrawPentagonFrame(vh, radius, lineWidth, gridColor);
            }

            for (int i = 0; i < 5; i++)
            {
                float angle = (Mathf.PI * 2f / 5f) * i + (Mathf.PI / 2f);
                Vector2 outerPt = new Vector2(Mathf.Cos(angle) * m_maxRadius, Mathf.Sin(angle) * m_maxRadius);
                DrawLine(vh, Vector2.zero, outerPt, lineWidth, gridColor);
            }

            Color32 fillCol = new Color32(212, 175, 55, 80);
            int fillCenterIdx = vh.currentVertCount;
            
            UIVertex centerVert = UIVertex.simpleVert;
            centerVert.color = fillCol;
            centerVert.position = Vector3.zero;
            vh.AddVert(centerVert);

            int startVertIdx = vh.currentVertCount;
            for (int i = 0; i < 5; i++)
            {
                float angle = (Mathf.PI * 2f / 5f) * i + (Mathf.PI / 2f);
                float val = m_emotionValues[i];
                float radius = m_maxRadius * (val / m_maxValue);
                
                UIVertex outerVert = UIVertex.simpleVert;
                outerVert.color = fillCol;
                outerVert.position = new Vector3(Mathf.Cos(angle) * radius, Mathf.Sin(angle) * radius, 0f);
                vh.AddVert(outerVert);
            }

            for (int i = 0; i < 5; i++)
            {
                int nextIdx = startVertIdx + ((i + 1) % 5);
                vh.AddTriangle(fillCenterIdx, startVertIdx + i, nextIdx);
            }

            Color32 outlineCol = new Color32(212, 175, 55, 255);
            for (int i = 0; i < 5; i++)
            {
                float angleA = (Mathf.PI * 2f / 5f) * i + (Mathf.PI / 2f);
                float valA = m_emotionValues[i];
                float radiusA = m_maxRadius * (valA / m_maxValue);
                Vector2 pA = new Vector2(Mathf.Cos(angleA) * radiusA, Mathf.Sin(angleA) * radiusA);

                float angleB = (Mathf.PI * 2f / 5f) * ((i + 1) % 5) + (Mathf.PI / 2f);
                float valB = m_emotionValues[(i + 1) % 5];
                float radiusB = m_maxRadius * (valB / m_maxValue);
                Vector2 pB = new Vector2(Mathf.Cos(angleB) * radiusB, Mathf.Sin(angleB) * radiusB);

                DrawLine(vh, pA, pB, 2f, outlineCol);
            }

            Color32[] emotionColors = new Color32[5]
            {
                new Color32(121, 146, 200, 255),
                new Color32(217, 184, 109, 255),
                new Color32(202, 181, 131, 255),
                new Color32(173, 77, 83, 255),
                new Color32(142, 114, 158, 255)
            };

            for (int i = 0; i < 5; i++)
            {
                float angle = (Mathf.PI * 2f / 5f) * i + (Mathf.PI / 2f);
                float val = m_emotionValues[i];
                float radius = m_maxRadius * (val / m_maxValue);
                Vector2 center = new Vector2(Mathf.Cos(angle) * radius, Mathf.Sin(angle) * radius);

                DrawCircleNode(vh, center, 5f, emotionColors[i]);
            }
        }

        private void DrawLine(VertexHelper vh, Vector2 pA, Vector2 pB, float width, Color32 col)
        {
            Vector2 dir = (pB - pA).normalized;
            Vector2 normal = new Vector2(-dir.y, dir.x) * (width * 0.5f);

            int startIdx = vh.currentVertCount;

            UIVertex v0 = UIVertex.simpleVert;
            v0.color = col;
            v0.position = pA - normal;
            vh.AddVert(v0);

            UIVertex v1 = UIVertex.simpleVert;
            v1.color = col;
            v1.position = pA + normal;
            vh.AddVert(v1);

            UIVertex v2 = UIVertex.simpleVert;
            v2.color = col;
            v2.position = pB + normal;
            vh.AddVert(v2);

            UIVertex v3 = UIVertex.simpleVert;
            v3.color = col;
            v3.position = pB - normal;
            vh.AddVert(v3);

            vh.AddTriangle(startIdx, startIdx + 1, startIdx + 2);
            vh.AddTriangle(startIdx, startIdx + 2, startIdx + 3);
        }

        private void DrawPentagonFrame(VertexHelper vh, float radius, float width, Color32 col)
        {
            for (int i = 0; i < 5; i++)
            {
                float angleA = (Mathf.PI * 2f / 5f) * i + (Mathf.PI / 2f);
                Vector2 pA = new Vector2(Mathf.Cos(angleA) * radius, Mathf.Sin(angleA) * radius);

                float angleB = (Mathf.PI * 2f / 5f) * ((i + 1) % 5) + (Mathf.PI / 2f);
                Vector2 pB = new Vector2(Mathf.Cos(angleB) * radius, Mathf.Sin(angleB) * radius);

                DrawLine(vh, pA, pB, width, col);
            }
        }

        private void DrawCircleNode(VertexHelper vh, Vector2 center, float radius, Color32 col)
        {
            int centerIdx = vh.currentVertCount;
            UIVertex cVert = UIVertex.simpleVert;
            cVert.color = col;
            cVert.position = center;
            vh.AddVert(cVert);

            int startVertIdx = vh.currentVertCount;
            int segments = 10;
            for (int i = 0; i < segments; i++)
            {
                float angle = (Mathf.PI * 2f / segments) * i;
                UIVertex v = UIVertex.simpleVert;
                v.color = col;
                v.position = center + new Vector2(Mathf.Cos(angle) * radius, Mathf.Sin(angle) * radius);
                vh.AddVert(v);
            }

            for (int i = 0; i < segments; i++)
            {
                int nextIdx = startVertIdx + ((i + 1) % segments);
                vh.AddTriangle(centerIdx, startVertIdx + i, nextIdx);
            }
        }
    }
}

using UnityEngine;
using UnityEngine.UI;
using TMPro;
using VContainer;
using Domain.InGame;

namespace Features.InGame
{
    [ExecuteAlways]
    public class InGameSidePanelView : MonoBehaviour
    {
        [Header("카토 재고 구성요소")]
        [UnityEngine.Serialization.FormerlySerializedAs("m_trustStockBlocks")]
        [SerializeField] private GameObject[] m_catoStockBlocks;
        [UnityEngine.Serialization.FormerlySerializedAs("m_trustStockText")]
        [SerializeField] private TextMeshProUGUI m_catoStockText;

        [Header("감정 5축 수치 텍스트")]
        [SerializeField] private TextMeshProUGUI m_sadnessText;
        [SerializeField] private TextMeshProUGUI m_joyText;
        [SerializeField] private TextMeshProUGUI m_curiosityText;
        [SerializeField] private TextMeshProUGUI m_fearText;
        [SerializeField] private TextMeshProUGUI m_confusionText;

        [Header("레이더 차트 렌더러")]
        [SerializeField] private UIRadarChartRenderer m_radarChart;

        [Header("현 상태 구성요소")]
        [SerializeField] private TextMeshProUGUI m_dominantEmotionText;
        [SerializeField] private TextMeshProUGUI m_yearningStatusText;

        [Header("감시 구성요소")]
        [SerializeField] private Slider m_monitoringSlider;
        [SerializeField] private TextMeshProUGUI m_monitoringText;

        [Header("신뢰도 구성요소")]
        [SerializeField] private Slider m_trustSlider;
        [SerializeField] private TextMeshProUGUI m_trustText;

        [Header("회차 인식 구성요소")]
        [SerializeField] private GameObject[] m_loopBlocks;
        [SerializeField] private TextMeshProUGUI m_loopText;

        [Header("회차 분기 텍스트")]
        [SerializeField] private TextMeshProUGUI m_actBranchText;
        [SerializeField] private TextMeshProUGUI m_passedScenesText;

        [SerializeField, Range(0, 10)] private int m_sadnessEditorVal = 6;
        [SerializeField, Range(0, 10)] private int m_joyEditorVal = 1;
        [SerializeField, Range(0, 10)] private int m_curiosityEditorVal = 7;
        [SerializeField, Range(0, 10)] private int m_fearEditorVal = 3;
        [SerializeField, Range(0, 10)] private int m_confusionEditorVal = 3;

        private ISidePanelViewModel m_viewModel;

        [Inject]
        public void Construct(ISidePanelViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnSidePanelDataChanged += UpdateSidePanelData;
        }

        private void Start()
        {
            SetInitialMockData();
        }

        private void SetInitialMockData()
        {
            UpdateStockBlocks(m_catoStockBlocks, 2);
            if (m_catoStockText != null)
            {
                m_catoStockText.text = "2 / 5";
            }

            UpdateSliderAndText(null, m_sadnessText, 6, 10);
            UpdateSliderAndText(null, m_joyText, 1, 10);
            UpdateSliderAndText(null, m_curiosityText, 7, 10);
            UpdateSliderAndText(null, m_fearText, 3, 10);
            UpdateSliderAndText(null, m_confusionText, 3, 10);

            if (m_radarChart != null)
            {
                m_radarChart.SetEmotionValues(6, 3, 3, 7, 1);
            }

            UpdateSliderAndText(m_monitoringSlider, m_monitoringText, 5, 10);
            UpdateSliderAndText(m_trustSlider, m_trustText, 4, 10);

            UpdateStockBlocks(m_loopBlocks, 1);
            if (m_loopText != null)
            {
                m_loopText.text = "1 / 5";
            }

            if (m_actBranchText != null)
            {
                m_actBranchText.text = "D1 · R · V · β";
            }

            if (m_passedScenesText != null)
            {
                m_passedScenesText.text = "씬 2 · 3 · 5 · 7";
            }

            UpdateTextsPosition();
            UpdateStatusText(6, 1, 7, 3, 3);
        }

        private void UpdateSidePanelData(SidePanelDTO data)
        {
            if (data == null)
            {
                return;
            }

            UpdateStockBlocks(m_catoStockBlocks, data.CatoStocks);
            if (m_catoStockText != null)
            {
                m_catoStockText.text = $"{data.CatoStocks} / {data.MaxCatoStocks}";
            }

            UpdateSliderAndText(null, m_sadnessText, data.Sadness, 10);
            UpdateSliderAndText(null, m_joyText, data.Joy, 10);
            UpdateSliderAndText(null, m_curiosityText, data.Curiosity, 10);
            UpdateSliderAndText(null, m_fearText, data.Fear, 10);
            UpdateSliderAndText(null, m_confusionText, data.Confusion, 10);

            if (m_radarChart != null)
            {
                m_radarChart.SetEmotionValues(data.Sadness, data.Confusion, data.Fear, data.Curiosity, data.Joy);
            }

            UpdateSliderAndText(m_monitoringSlider, m_monitoringText, data.Monitoring, 10);
            UpdateSliderAndText(m_trustSlider, m_trustText, data.Trust, 10);

            UpdateStockBlocks(m_loopBlocks, data.LoopAwareness);
            if (m_loopText != null)
            {
                m_loopText.text = $"{data.LoopAwareness} / {data.MaxLoopAwareness}";
            }

            if (m_actBranchText != null)
            {
                m_actBranchText.text = data.ActBranchInfo;
            }

            if (m_passedScenesText != null)
            {
                m_passedScenesText.text = data.PassedScenesInfo;
            }

            UpdateTextsPosition();
            UpdateStatusText(data.Sadness, data.Joy, data.Curiosity, data.Fear, data.Confusion);
        }

        private void UpdateStockBlocks(GameObject[] blocks, int count)
        {
            if (blocks == null)
            {
                return;
            }

            for (int i = 0; i < blocks.Length; i++)
            {
                if (blocks[i] != null)
                {
                    if (i < count)
                    {
                        blocks[i].SetActive(true);
                    }
                    else
                    {
                        blocks[i].SetActive(false);
                    }
                }
            }
        }

        private void UpdateSliderAndText(Slider slider, TextMeshProUGUI text, int value, int max)
        {
            if (slider != null)
            {
                slider.value = (float)value / max;
            }

            if (text != null)
            {
                string emotionName = "";
                if (text == m_sadnessText)
                {
                    emotionName = "슬픔";
                }
                else if (text == m_joyText)
                {
                    emotionName = "기쁨";
                }
                else if (text == m_curiosityText)
                {
                    emotionName = "호기심";
                }
                else if (text == m_fearText)
                {
                    emotionName = "공포";
                }
                else if (text == m_confusionText)
                {
                    emotionName = "혼란";
                }

                if (string.IsNullOrEmpty(emotionName) == false)
                {
                    string colorHex = "";
                    if (emotionName == "슬픔")
                    {
                        colorHex = "#7992C8";
                    }
                    else if (emotionName == "기쁨")
                    {
                        colorHex = "#D9B86D";
                    }
                    else if (emotionName == "호기심")
                    {
                        colorHex = "#CAB583";
                    }
                    else if (emotionName == "공포")
                    {
                        colorHex = "#AD4D53";
                    }
                    else if (emotionName == "혼란")
                    {
                        colorHex = "#8E729E";
                    }

                    text.text = $"<color={colorHex}>{emotionName}</color>\n<color=#D4AF37><b>{value}</b></color>";
                }
                else
                {
                    text.text = $"{value} / {max}";
                }
            }
        }

        private void UpdateTextsPosition()
        {
            if (m_radarChart != null)
            {
                RectTransform chartRect = m_radarChart.GetComponent<RectTransform>();
                if (chartRect != null)
                {
                    Vector2 center = chartRect.anchoredPosition;
                    float textRadius = 180f;

                    RectTransform[] textRects = new RectTransform[5]
                    {
                        m_sadnessText != null ? m_sadnessText.rectTransform : null,
                        m_confusionText != null ? m_confusionText.rectTransform : null,
                        m_fearText != null ? m_fearText.rectTransform : null,
                        m_curiosityText != null ? m_curiosityText.rectTransform : null,
                        m_joyText != null ? m_joyText.rectTransform : null
                    };

                    for (int i = 0; i < 5; i++)
                    {
                        if (textRects[i] != null)
                        {
                            textRects[i].anchorMin = new Vector2(0.5f, 0.5f);
                            textRects[i].anchorMax = new Vector2(0.5f, 0.5f);

                            float angle = (Mathf.PI * 2f / 5f) * i + (Mathf.PI / 2f);
                            float x = center.x + Mathf.Cos(angle) * textRadius;
                            float y = center.y + Mathf.Sin(angle) * textRadius;
                            textRects[i].anchoredPosition = new Vector2(x, y);

                            float cos = Mathf.Cos(angle);
                            float sin = Mathf.Sin(angle);
                            float pivotX = 0.5f - cos * 0.5f;
                            float pivotY = 0.5f - sin * 0.5f;
                            textRects[i].pivot = new Vector2(pivotX, pivotY);
                        }
                    }
                }
            }
        }

        private void UpdateStatusText(int sadness, int joy, int curiosity, int fear, int confusion)
        {
            int maxVal = -1;
            string dominantName = "";
            int[] vals = new int[5] { sadness, joy, curiosity, fear, confusion };
            string[] names = new string[5] { "슬픔", "기쁨", "호기심", "공포", "혼란" };

            for (int i = 0; i < 5; i++)
            {
                if (vals[i] > maxVal)
                {
                    maxVal = vals[i];
                    dominantName = names[i];
                }
            }

            if (m_dominantEmotionText != null)
            {
                m_dominantEmotionText.text = $"우세 감정:  <color=#D4AF37>{dominantName} ({maxVal})</color>";
            }

            if (m_yearningStatusText != null)
            {
                if (sadness >= 3 && joy >= 3)
                {
                    m_yearningStatusText.text = "그리움:  <color=#D4AF37>활성</color>";
                }
                else
                {
                    string reason = "";
                    if (sadness < 3 && joy < 3)
                    {
                        reason = "슬픔, 기쁨 < 3";
                    }
                    else if (sadness < 3)
                    {
                        reason = "슬픔 < 3";
                    }
                    else
                    {
                        reason = "기쁨 < 3";
                    }
                    m_yearningStatusText.text = $"그리움:  <color=#888888>비활성 ({reason})</color>";
                }
            }
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnSidePanelDataChanged -= UpdateSidePanelData;
            }
        }

        private void UpdateEditorMockData()
        {
            UpdateStockBlocks(m_catoStockBlocks, 2);
            if (m_catoStockText != null)
            {
                m_catoStockText.text = "2 / 5";
            }

            UpdateSliderAndText(null, m_sadnessText, m_sadnessEditorVal, 10);
            UpdateSliderAndText(null, m_joyText, m_joyEditorVal, 10);
            UpdateSliderAndText(null, m_curiosityText, m_curiosityEditorVal, 10);
            UpdateSliderAndText(null, m_fearText, m_fearEditorVal, 10);
            UpdateSliderAndText(null, m_confusionText, m_confusionEditorVal, 10);

            if (m_radarChart != null)
            {
                m_radarChart.SetEmotionValues(m_sadnessEditorVal, m_confusionEditorVal, m_fearEditorVal, m_curiosityEditorVal, m_joyEditorVal);
            }

            UpdateSliderAndText(m_monitoringSlider, m_monitoringText, 5, 10);
            UpdateSliderAndText(m_trustSlider, m_trustText, 4, 10);

            UpdateStockBlocks(m_loopBlocks, 1);
            if (m_loopText != null)
            {
                m_loopText.text = "1 / 5";
            }

            if (m_actBranchText != null)
            {
                m_actBranchText.text = "D1 · R · V · β";
            }

            if (m_passedScenesText != null)
            {
                m_passedScenesText.text = "씬 2 · 3 · 5 · 7";
            }

            UpdateTextsPosition();
            UpdateStatusText(m_sadnessEditorVal, m_joyEditorVal, m_curiosityEditorVal, m_fearEditorVal, m_confusionEditorVal);
        }

        private void OnValidate()
        {
            if (Application.isPlaying == false)
            {
                UpdateEditorMockData();
            }
        }
    }
}

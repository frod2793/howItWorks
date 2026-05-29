using UnityEngine;
using UnityEngine.UI;
using TMPro;
using VContainer;
using Domain.InGame;

namespace Features.InGame
{
    public class InGameSidePanelView : MonoBehaviour
    {
        [Header("카토 재고 구성요소")]
        [SerializeField] private GameObject[] m_trustStockBlocks;
        [SerializeField] private TextMeshProUGUI m_trustStockText;

        [Header("감정 5축 슬라이더")]
        [SerializeField] private Slider m_sadnessSlider;
        [SerializeField] private Slider m_joySlider;
        [SerializeField] private Slider m_curiositySlider;
        [SerializeField] private Slider m_fearSlider;
        [SerializeField] private Slider m_confusionSlider;

        [Header("감정 5축 수치 텍스트")]
        [SerializeField] private TextMeshProUGUI m_sadnessText;
        [SerializeField] private TextMeshProUGUI m_joyText;
        [SerializeField] private TextMeshProUGUI m_curiosityText;
        [SerializeField] private TextMeshProUGUI m_fearText;
        [SerializeField] private TextMeshProUGUI m_confusionText;

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
            UpdateStockBlocks(m_trustStockBlocks, 2);
            if (m_trustStockText != null)
            {
                m_trustStockText.text = "2 / 5";
            }

            UpdateSliderAndText(m_sadnessSlider, m_sadnessText, 6, 10);
            UpdateSliderAndText(m_joySlider, m_joyText, 1, 10);
            UpdateSliderAndText(m_curiositySlider, m_curiosityText, 7, 10);
            UpdateSliderAndText(m_fearSlider, m_fearText, 3, 10);
            UpdateSliderAndText(m_confusionSlider, m_confusionText, 3, 10);

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
        }

        private void UpdateSidePanelData(SidePanelDTO data)
        {
            if (data == null)
            {
                return;
            }

            UpdateStockBlocks(m_trustStockBlocks, data.TrustStocks);
            if (m_trustStockText != null)
            {
                m_trustStockText.text = $"{data.TrustStocks} / {data.MaxTrustStocks}";
            }

            UpdateSliderAndText(m_sadnessSlider, m_sadnessText, data.Sadness, 10);
            UpdateSliderAndText(m_joySlider, m_joyText, data.Joy, 10);
            UpdateSliderAndText(m_curiositySlider, m_curiosityText, data.Curiosity, 10);
            UpdateSliderAndText(m_fearSlider, m_fearText, data.Fear, 10);
            UpdateSliderAndText(m_confusionSlider, m_confusionText, data.Confusion, 10);

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
                text.text = $"{value}/{max}";
            }
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnSidePanelDataChanged -= UpdateSidePanelData;
            }
        }
    }
}

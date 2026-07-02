using UnityEngine;
using UnityEngine.UI;
using TMPro;
using VContainer;
using Domain.InGame;
using DG.Tweening;
using Cysharp.Threading.Tasks;
using System.Threading;
using System.Collections.Generic;

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

        [Header("진행 컨트롤 버튼")]
        [SerializeField] private Button m_autoButton;
        [SerializeField] private Button m_skipButton;
        [SerializeField] private Button m_logButton;
        [SerializeField] private Button m_inventoryButton;

        [SerializeField, Range(0, 10)] private int m_sadnessEditorVal = 6;
        [SerializeField, Range(0, 10)] private int m_joyEditorVal = 1;
        [SerializeField, Range(0, 10)] private int m_curiosityEditorVal = 7;
        [SerializeField, Range(0, 10)] private int m_fearEditorVal = 3;
        [SerializeField, Range(0, 10)] private int m_confusionEditorVal = 3;

        private ISidePanelViewModel m_viewModel;
        private IDialogueViewModel m_dialogueViewModel;
        private Tweener m_monitoringPulseTween;
        private bool m_isSkipActive;
        private CancellationTokenSource m_skipCts;

        [Inject]
        public void Construct(ISidePanelViewModel viewModel, IDialogueViewModel dialogueViewModel)
        {
            m_viewModel = viewModel;
            m_dialogueViewModel = dialogueViewModel;

            m_viewModel.OnSidePanelDataChanged += UpdateSidePanelData;
            m_dialogueViewModel.OnAutoPlayStatusChanged += SyncAutoPlayState;
            m_dialogueViewModel.OnChoicesUpdated += HandleChoicesUpdated;
        }

        private void Start()
        {
            SetInitialMockData();

            if (m_autoButton != null)
            {
                m_autoButton.onClick.RemoveAllListeners();
                m_autoButton.onClick.AddListener(func_OnAutoButtonClicked);
            }

            if (m_skipButton != null)
            {
                m_skipButton.onClick.RemoveAllListeners();
                m_skipButton.onClick.AddListener(func_OnSkipButtonClicked);
            }

            if (m_logButton != null)
            {
                m_logButton.onClick.RemoveAllListeners();
                m_logButton.onClick.AddListener(func_OnLogButtonClicked);
            }

            if (m_inventoryButton != null)
            {
                m_inventoryButton.onClick.RemoveAllListeners();
                m_inventoryButton.onClick.AddListener(func_OnInventoryButtonClicked);
            }
        }

        private void SetInitialMockData()
        {
            UpdateStockBlocks(m_catoStockBlocks, 3);
            if (m_catoStockText != null)
            {
                m_catoStockText.text = "3 / 5";
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

            UpdateSliderAndText(m_monitoringSlider, m_monitoringText, 2, 10);
            UpdateSliderAndText(m_trustSlider, m_trustText, 4, 10);

            UpdateStockBlocks(m_loopBlocks, 3);
            if (m_loopText != null)
            {
                m_loopText.text = "3 / 5";
            }

            if (m_actBranchText != null)
            {
                m_actBranchText.text = "D1 · R · V · β";
            }

            if (m_passedScenesText != null)
            {
                m_passedScenesText.text = "씬 2 · 3 · 5 · 7";
            }

            UpdateStatusText(6, 1, 7, 3, 3, (6 >= 3 && 1 >= 3));
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

            UpdateStatusText(data.Sadness, data.Joy, data.Curiosity, data.Fear, data.Confusion, data.IsLongingActive);
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

                if (slider == m_monitoringSlider)
                {
                    var fillImage = slider.fillRect != null ? slider.fillRect.GetComponent<Image>() : null;
                    if (fillImage != null)
                    {
                        if (value >= 8)
                        {
                            if (m_monitoringPulseTween == null)
                            {
                                m_monitoringPulseTween = fillImage.DOColor(Color.red, 0.5f)
                                    .SetLoops(-1, LoopType.Yoyo)
                                    .SetUpdate(true);
                            }
                        }
                        else
                        {
                            if (m_monitoringPulseTween != null)
                            {
                                m_monitoringPulseTween.Kill();
                                m_monitoringPulseTween = null;
                                fillImage.color = new Color(0.68f, 0.3f, 0.33f, 1f);
                            }
                        }
                    }
                }
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



        private void UpdateStatusText(int sadness, int joy, int curiosity, int fear, int confusion, bool isLongingActive)
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
                if (isLongingActive)
                {
                    m_yearningStatusText.text = "그리움:  <color=#D4AF37>활성</color>";
                }
                else
                {
                    m_yearningStatusText.text = "그리움:  <color=#888888>비활성</color>";
                }
            }
        }

        private void OnDestroy()
        {
            func_CancelSkipLoop();

            if (m_monitoringPulseTween != null)
            {
                m_monitoringPulseTween.Kill();
                m_monitoringPulseTween = null;
            }

            if (m_viewModel != null)
            {
                m_viewModel.OnSidePanelDataChanged -= UpdateSidePanelData;
            }

            if (m_dialogueViewModel != null)
            {
                m_dialogueViewModel.OnAutoPlayStatusChanged -= SyncAutoPlayState;
                m_dialogueViewModel.OnChoicesUpdated -= HandleChoicesUpdated;
            }
        }

        public void func_OnAutoButtonClicked()
        {
            if (m_dialogueViewModel != null)
            {
                m_dialogueViewModel.IsAutoPlayActive = !m_dialogueViewModel.IsAutoPlayActive;
            }
        }

        public void func_OnSkipButtonClicked()
        {
            m_isSkipActive = !m_isSkipActive;
            if (m_isSkipActive)
            {
                if (m_dialogueViewModel != null)
                {
                    m_dialogueViewModel.IsAutoPlayActive = false;
                }
                func_RunSkipLoop().Forget();
            }
            else
            {
                func_CancelSkipLoop();
            }
        }

        public void func_OnLogButtonClicked()
        {
            if (m_dialogueViewModel != null)
            {
                m_dialogueViewModel.RequestBacklog();
            }
        }

        public void func_OnInventoryButtonClicked()
        {
        }

        private void SyncAutoPlayState(bool isAuto)
        {
            if (m_autoButton != null)
            {
                Image image = m_autoButton.GetComponent<Image>();
                if (image != null)
                {
                    if (isAuto)
                    {
                        image.color = new Color(Random.value, Random.value, Random.value, 1f);
                    }
                    else
                    {
                        image.color = Color.white;
                    }
                }
            }
        }

        private void HandleChoicesUpdated(List<DialogueChoiceDTO> choices)
        {
            if (choices != null && choices.Count > 0)
            {
                func_CancelSkipLoop();
            }
        }

        private async UniTaskVoid func_RunSkipLoop()
        {
            func_CancelSkipLoop();
            m_skipCts = new System.Threading.CancellationTokenSource();

            try
            {
                while (m_isSkipActive)
                {
                    if (m_dialogueViewModel != null)
                    {
                        m_dialogueViewModel.RequestSkip();
                        m_dialogueViewModel.RequestNext();
                    }
                    await UniTask.Delay(System.TimeSpan.FromSeconds(0.1f), cancellationToken: m_skipCts.Token);
                }
            }
            catch (System.OperationCanceledException)
            {
            }
        }

        private void func_CancelSkipLoop()
        {
            if (m_skipCts != null)
            {
                m_skipCts.Cancel();
                m_skipCts.Dispose();
                m_skipCts = null;
            }
            m_isSkipActive = false;
        }

        private void UpdateEditorMockData()
        {
            UpdateStockBlocks(m_catoStockBlocks, 3);
            if (m_catoStockText != null)
            {
                m_catoStockText.text = "3 / 5";
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

            UpdateSliderAndText(m_monitoringSlider, m_monitoringText, 2, 10);
            UpdateSliderAndText(m_trustSlider, m_trustText, 4, 10);

            UpdateStockBlocks(m_loopBlocks, 3);
            if (m_loopText != null)
            {
                m_loopText.text = "3 / 5";
            }

            if (m_actBranchText != null)
            {
                m_actBranchText.text = "D1 · R · V · β";
            }

            if (m_passedScenesText != null)
            {
                m_passedScenesText.text = "씬 2 · 3 · 5 · 7";
            }

            UpdateStatusText(m_sadnessEditorVal, m_joyEditorVal, m_curiosityEditorVal, m_fearEditorVal, m_confusionEditorVal, (m_sadnessEditorVal >= 3 && m_joyEditorVal >= 3));
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

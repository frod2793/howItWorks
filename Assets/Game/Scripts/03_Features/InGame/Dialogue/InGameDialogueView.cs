using System.Collections.Generic;
using System.Threading;
using Cysharp.Threading.Tasks;
using Domain.InGame;
using TMPro;
using UnityEngine;
using UnityEngine.UI;
using VContainer;

namespace Features.InGame
{
    public class InGameDialogueView : MonoBehaviour
    {
        [Header("UI 구성 요소")]
        [SerializeField] private Image m_speakerIcon;
        [SerializeField] private GameObject m_speakerBox;
        [SerializeField] private TextMeshProUGUI m_nameText;
        [SerializeField] private TextMeshProUGUI m_contentText;
        [SerializeField] private TypewriterEffect m_typewriterEffect;
        [SerializeField] private TextMeshProUGUI m_lineProgressText;

        private Image m_backgroundImage;
        private IDialogueViewModel m_viewModel;
        private CanvasGroup m_viewCanvasGroup;
        private bool m_isUIHidden = false;
        private CancellationTokenSource m_autoCts;



        [Inject]
        public void Construct(IDialogueViewModel viewModel)
        {
            m_viewModel = viewModel;

            m_viewModel.OnDialogueUpdated -= UpdateDialogue;
            m_viewModel.OnDialogueUpdated += UpdateDialogue;

            m_viewModel.OnChoicesUpdated -= HandleChoicesUpdated;
            m_viewModel.OnChoicesUpdated += HandleChoicesUpdated;

            m_viewModel.OnSkipRequested += () =>
            {
                if (m_typewriterEffect != null)
                {
                    m_typewriterEffect.Skip();
                }
            };

            m_backgroundImage = GetComponent<Image>();

            if (m_backgroundImage != null)
            {
                Color color = m_backgroundImage.color;
                color.a = 0.85f;
                m_backgroundImage.color = color;
            }
        }

        private void Start()
        {
            m_viewCanvasGroup = GetComponent<CanvasGroup>();
            if (m_viewCanvasGroup == null)
            {
                m_viewCanvasGroup = gameObject.AddComponent<CanvasGroup>();
            }
        }

        public void func_OnNextButtonClicked()
        {
            if (m_viewModel != null)
            {
                m_viewModel.RequestNext();
            }
        }

        private void Update()
        {
            var keyboard = UnityEngine.InputSystem.Keyboard.current;
            if (keyboard != null)
            {
                if (keyboard.hKey.wasPressedThisFrame)
                {
                    func_ToggleUIHide();
                }
                else if (keyboard.spaceKey.wasPressedThisFrame)
                {
                    func_OnNextButtonClicked();
                }
            }
        }

        private void func_ToggleUIHide()
        {
            m_isUIHidden = !m_isUIHidden;
            if (m_viewCanvasGroup != null)
            {
                m_viewCanvasGroup.alpha = m_isUIHidden ? 0f : 1f;
                m_viewCanvasGroup.blocksRaycasts = !m_isUIHidden;
                m_viewCanvasGroup.interactable = !m_isUIHidden;
            }
        }

        private void UpdateDialogue(DialogueDTO dialogue)
        {
            if (this == null)
            {
                return;
            }

            if (m_lineProgressText != null)
            {
                m_lineProgressText.text = $"{dialogue.CurrentLine} / {dialogue.TotalLines}";
            }

            if (dialogue.Type == DialogueType.Narration)
            {
                if (m_speakerBox != null)
                {
                    m_speakerBox.SetActive(false);
                }
                if (m_speakerIcon != null)
                {
                    m_speakerIcon.gameObject.SetActive(false);
                }
                if (m_contentText != null)
                {
                    m_contentText.text = "";
                }
                m_viewModel.IsTyping = true;
                if (m_typewriterEffect != null && m_contentText != null)
                {
                    m_typewriterEffect.Play(m_contentText, dialogue.Content, () =>
                    {
                        m_viewModel.IsTyping = false;
                        if (m_viewModel.IsAutoPlayActive)
                        {
                            func_RunAutoPlayDelay(dialogue.Content).Forget();
                        }
                    }).Forget();
                }
                else if (m_contentText != null)
                {
                    m_contentText.text = dialogue.Content;
                    m_viewModel.IsTyping = false;
                    if (m_viewModel.IsAutoPlayActive)
                    {
                        func_RunAutoPlayDelay(dialogue.Content).Forget();
                    }
                }
            }
            else if (dialogue.Type == DialogueType.SystemMessage)
            {
                if (m_speakerBox != null)
                {
                    m_speakerBox.SetActive(false);
                }
                if (m_speakerIcon != null)
                {
                    m_speakerIcon.gameObject.SetActive(false);
                }
                if (m_contentText != null)
                {
                    m_contentText.text = "";
                }
                m_viewModel.IsTyping = true;
                if (m_typewriterEffect != null && m_contentText != null)
                {
                    m_typewriterEffect.Play(m_contentText, dialogue.Content, () =>
                    {
                        m_viewModel.IsTyping = false;
                        if (m_viewModel.IsAutoPlayActive)
                        {
                            func_RunAutoPlayDelay(dialogue.Content).Forget();
                        }
                    }).Forget();
                }
                else if (m_contentText != null)
                {
                    m_contentText.text = dialogue.Content;
                    m_viewModel.IsTyping = false;
                    if (m_viewModel.IsAutoPlayActive)
                    {
                        func_RunAutoPlayDelay(dialogue.Content).Forget();
                    }
                }
            }
            else
            {
                if (m_speakerBox != null)
                {
                    m_speakerBox.SetActive(true);
                }
                if (m_nameText != null)
                {
                    m_nameText.text = dialogue.SpeakerName;
                }
                if (m_speakerIcon != null)
                {
                    if (string.IsNullOrEmpty(dialogue.SpeakerIconKey))
                    {
                        m_speakerIcon.gameObject.SetActive(false);
                    }
                    else
                    {
                        m_speakerIcon.gameObject.SetActive(true);
                    }
                }
                if (m_contentText != null)
                {
                    m_contentText.text = "";
                }
                m_viewModel.IsTyping = true;
                if (m_typewriterEffect != null && m_contentText != null)
                {
                    m_typewriterEffect.Play(m_contentText, dialogue.Content, () =>
                    {
                        m_viewModel.IsTyping = false;
                        if (m_viewModel.IsAutoPlayActive)
                        {
                            func_RunAutoPlayDelay(dialogue.Content).Forget();
                        }
                    }).Forget();
                }
                else if (m_contentText != null)
                {
                    m_contentText.text = dialogue.Content;
                    m_viewModel.IsTyping = false;
                    if (m_viewModel.IsAutoPlayActive)
                    {
                        func_RunAutoPlayDelay(dialogue.Content).Forget();
                    }
                }
            }
        }

        private async UniTaskVoid func_RunAutoPlayDelay(string content)
        {
            func_CancelAutoTimer();
            m_autoCts = new CancellationTokenSource();

            try
            {
                float delayTime = content.Length * 0.05f + 1.5f;
                await UniTask.Delay(System.TimeSpan.FromSeconds(delayTime), cancellationToken: m_autoCts.Token);
                func_OnNextButtonClicked();
            }
            catch (System.OperationCanceledException)
            {
            }
        }

        private void func_CancelAutoTimer()
        {
            if (m_autoCts != null)
            {
                m_autoCts.Cancel();
                m_autoCts.Dispose();
                m_autoCts = null;
            }
        }

        private void HandleChoicesUpdated(List<DialogueChoiceDTO> choices)
        {
            if (this == null)
            {
                return;
            }

            int activeCount = 0;
            if (choices != null)
            {
                for (int i = 0; i < choices.Count; i++)
                {
                    if (choices[i] != null && !choices[i].IsLocked)
                    {
                        activeCount++;
                    }
                }
            }

            if (activeCount > 0)
            {
                func_CancelAutoTimer();
                if (m_viewModel != null)
                {
                    m_viewModel.IsAutoPlayActive = false;
                }
            }
        }

        private void OnDestroy()
        {
            func_CancelAutoTimer();
            if (m_viewModel != null)
            {
                m_viewModel.OnDialogueUpdated -= UpdateDialogue;
                m_viewModel.OnChoicesUpdated -= HandleChoicesUpdated;
            }
        }
    }
}

using UnityEngine;
using UnityEngine.UI;
using TMPro;
using VContainer;
using Cysharp.Threading.Tasks;
using System.Threading;
using Domain.InGame;

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
        [SerializeField] private Button m_autoButton;
        [SerializeField] private Button m_inventoryButton;
        [SerializeField] private TextMeshProUGUI m_lineProgressText;

        private Image m_backgroundImage;
        private IDialogueViewModel m_viewModel;

        private bool m_isAutoMode = false;
        private CancellationTokenSource m_autoProceedCts;

        [Inject]
        public void Construct(IDialogueViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnDialogueUpdated += UpdateDialogue;
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

        public void func_OnNextButtonClicked()
        {
            if (m_viewModel != null)
            {
                m_viewModel.RequestNext();
            }
        }

        public void func_OnAutoButtonClicked()
        {
            if (m_autoButton != null)
            {
                var image = m_autoButton.GetComponent<Image>();
                if (image != null)
                {
                    if (!m_isAutoMode)
                    {
                        image.color = new Color(Random.value, Random.value, Random.value, 1f);
                    }
                    else
                    {
                        image.color = Color.white;
                    }
                }
            }

            m_isAutoMode = !m_isAutoMode;
            if (m_isAutoMode)
            {
                StartAutoProceed().Forget();
            }
            else
            {
                CancelAutoProceed();
            }
        }

        public void func_OnSkipButtonClicked()
        {
        }

        public void func_OnLogButtonClicked()
        {
            if (m_viewModel != null)
            {
                m_viewModel.RequestBacklog();
            }
        }

        public void func_OnInventoryButtonClicked()
        {
        }

        private async UniTaskVoid StartAutoProceed()
        {
            CancelAutoProceed();
            m_autoProceedCts = new CancellationTokenSource();
            var token = m_autoProceedCts.Token;

            try
            {
                while (m_isAutoMode)
                {
                    await UniTask.WaitUntil(() => { return !m_viewModel.IsTyping; }, cancellationToken: token);
                    await UniTask.Delay(System.TimeSpan.FromSeconds(2.0f), cancellationToken: token);

                    if (m_isAutoMode && m_viewModel != null)
                    {
                        m_viewModel.RequestNext();
                    }
                }
            }
            catch (System.OperationCanceledException)
            {
            }
        }

        private void CancelAutoProceed()
        {
            if (m_autoProceedCts != null)
            {
                m_autoProceedCts.Cancel();
                m_autoProceedCts.Dispose();
                m_autoProceedCts = null;
            }
        }

        private void UpdateDialogue(DialogueDTO dialogue)
        {
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
                m_viewModel.IsTyping = true;
                if (m_typewriterEffect != null && m_contentText != null)
                {
                    m_typewriterEffect.Play(m_contentText, dialogue.Content, () => { m_viewModel.IsTyping = false; }).Forget();
                }
                else if (m_contentText != null)
                {
                    m_contentText.text = dialogue.Content;
                    m_viewModel.IsTyping = false;
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
                    if (m_typewriterEffect != null)
                    {
                        m_typewriterEffect.Stop();
                    }
                    m_contentText.text = dialogue.Content;
                    m_viewModel.IsTyping = false;
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
                m_viewModel.IsTyping = true;
                if (m_typewriterEffect != null && m_contentText != null)
                {
                    m_typewriterEffect.Play(m_contentText, dialogue.Content, () => { m_viewModel.IsTyping = false; }).Forget();
                }
                else if (m_contentText != null)
                {
                    m_contentText.text = dialogue.Content;
                    m_viewModel.IsTyping = false;
                }
            }
        }

        private void HandleChoicesUpdated(System.Collections.Generic.List<DialogueChoiceDTO> choices)
        {
            if (choices != null && choices.Count > 0)
            {
                gameObject.SetActive(false);
            }
            else
            {
                gameObject.SetActive(true);
            }
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnDialogueUpdated -= UpdateDialogue;
                m_viewModel.OnChoicesUpdated -= HandleChoicesUpdated;
            }
            CancelAutoProceed();
        }
    }
}

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



        [Inject]
        public void Construct(IDialogueViewModel viewModel)
        {
            m_viewModel = viewModel;

            m_viewModel.OnDialogueUpdated -= UpdateDialogue;
            m_viewModel.OnDialogueUpdated += UpdateDialogue;

            m_viewModel.OnChoicesUpdated -= HandleChoicesUpdated;
            m_viewModel.OnChoicesUpdated += HandleChoicesUpdated;

            m_viewModel.OnAutoPlayStatusChanged -= SyncAutoPlayState;
            m_viewModel.OnAutoPlayStatusChanged += SyncAutoPlayState;

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
            if (m_viewModel != null)
            {
                Debug.Log($"[InGameDialogueView] 오토 버튼 클릭됨. 토글 요청: {!m_viewModel.IsAutoPlayActive}");
                m_viewModel.IsAutoPlayActive = !m_viewModel.IsAutoPlayActive;
            }
        }

        private void SyncAutoPlayState(bool isAuto)
        {
            Debug.Log($"[InGameDialogueView] 오토플레이 상태 변경 이벤트 수신: {isAuto}");
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
                    m_contentText.text = "";
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
            if (this == null)
            {
                return;
            }

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
                m_viewModel.OnAutoPlayStatusChanged -= SyncAutoPlayState;
            }
        }
    }
}

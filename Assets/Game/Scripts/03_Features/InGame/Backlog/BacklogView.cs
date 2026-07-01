using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using TMPro;
using Domain.InGame;

namespace Features.InGame
{
    public class BacklogView : MonoBehaviour
    {
        [SerializeField] private GameObject m_backlogPanel;
        [SerializeField] private TMP_Text m_sceneInfoText;
        [SerializeField] private TMP_Text m_guideText;
        [SerializeField] private GameObject m_itemPrefab;
        [SerializeField] private RectTransform m_contentParent;
        [SerializeField] private GameObject m_warningPopup;
        [SerializeField] private Button m_confirmJumpButton;
        [SerializeField] private Button m_cancelJumpButton;

        private IBacklogViewModel m_viewModel;
        private List<GameObject> m_spawnedItems = new List<GameObject>();
        private int m_pendingJumpIndex = -1;

        public void Initialize(IBacklogViewModel viewModel)
        {
            if (viewModel == null)
            {
                return;
            }
            m_viewModel = viewModel;
            m_viewModel.OnBacklogUpdated += UpdateUIValues;

            if (m_itemPrefab != null)
            {
                m_itemPrefab.SetActive(false);
            }

            if (m_confirmJumpButton != null)
            {
                m_confirmJumpButton.onClick.RemoveAllListeners();
                m_confirmJumpButton.onClick.AddListener(func_OnConfirmJumpClicked);
            }
            if (m_cancelJumpButton != null)
            {
                m_cancelJumpButton.onClick.RemoveAllListeners();
                m_cancelJumpButton.onClick.AddListener(func_OnCancelJumpClicked);
            }

            if (m_warningPopup != null)
            {
                m_warningPopup.SetActive(false);
            }

            UpdateUIValues();
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnBacklogUpdated -= UpdateUIValues;
            }
        }

        private void UpdateUIValues()
        {
            if (m_viewModel == null)
            {
                return;
            }
            if (m_sceneInfoText != null)
            {
                m_sceneInfoText.text = $"{m_viewModel.CurrentSceneInfo} · {m_viewModel.Items.Count} 줄";
            }
        }

        public void func_Open()
        {
            if (m_backlogPanel != null)
            {
                m_backlogPanel.SetActive(true);
            }

            UpdateUIValues();

            for (int i = 0; i < m_spawnedItems.Count; i++)
            {
                if (m_spawnedItems[i] != null)
                {
                    Destroy(m_spawnedItems[i]);
                }
            }
            m_spawnedItems.Clear();

            if (m_viewModel == null || m_itemPrefab == null || m_contentParent == null)
            {
                return;
            }

            for (int i = 0; i < m_viewModel.Items.Count; i++)
            {
                var data = m_viewModel.Items[i];
                var inst = Instantiate(m_itemPrefab, m_contentParent);
                if (inst != null)
                {
                    inst.SetActive(true);
                    m_spawnedItems.Add(inst);

                    var speakerTrans = inst.transform.Find("SpeakerText");
                    var speakerText = speakerTrans != null ? speakerTrans.GetComponent<TMP_Text>() : null;
                    var contentTrans = inst.transform.Find("ContentText");
                    var contentText = contentTrans != null ? contentTrans.GetComponent<TMP_Text>() : null;
                    var branchTag = inst.transform.Find("BranchTag");
                    var bgImage = inst.GetComponent<Image>();

                    if (speakerText != null)
                    {
                        speakerText.text = data.SpeakerName;
                        if (data.Type == DialogueType.Narration)
                        {
                            speakerText.color = new Color(0.5f, 0.5f, 0.5f, 1f);
                        }
                        else if (data.Type == DialogueType.SystemMessage)
                        {
                            speakerText.color = new Color(1f, 0.75f, 0f, 1f);
                        }
                        else
                        {
                            speakerText.color = Color.white;
                        }
                    }

                    if (contentText != null)
                    {
                        contentText.text = data.Content;
                    }

                    if (branchTag != null)
                    {
                        branchTag.gameObject.SetActive(data.HasBranchEffect);
                    }

                    if (bgImage != null)
                    {
                        if (data.HasBranchEffect)
                        {
                            bgImage.color = new Color(1f, 0.55f, 0f, 0.2f);
                        }
                        else
                        {
                            bgImage.color = new Color(0.1f, 0.1f, 0.1f, 0.4f);
                        }
                    }

                    var jumpBtnTrans = inst.transform.Find("JumpButton");
                    var jumpBtn = jumpBtnTrans != null ? jumpBtnTrans.GetComponent<Button>() : null;
                    if (jumpBtn != null)
                    {
                        int targetIdx = data.DialogueIndex;
                        jumpBtn.onClick.RemoveAllListeners();
                        jumpBtn.onClick.AddListener(() => func_RequestJump(targetIdx));
                    }
                }
            }
        }

        public void func_Close()
        {
            if (m_backlogPanel != null)
            {
                m_backlogPanel.SetActive(false);
            }
        }

        private void func_RequestJump(int dialogueIndex)
        {
            m_pendingJumpIndex = dialogueIndex;
            if (m_warningPopup != null)
            {
                m_warningPopup.SetActive(true);
            }
        }

        public void func_OnConfirmJumpClicked()
        {
            if (m_pendingJumpIndex != -1 && m_viewModel != null)
            {
                m_viewModel.JumpToLine(m_pendingJumpIndex);
            }

            m_pendingJumpIndex = -1;
            if (m_warningPopup != null)
            {
                m_warningPopup.SetActive(false);
            }
            func_Close();
        }

        public void func_OnCancelJumpClicked()
        {
            m_pendingJumpIndex = -1;
            if (m_warningPopup != null)
            {
                m_warningPopup.SetActive(false);
            }
        }
    }
}
